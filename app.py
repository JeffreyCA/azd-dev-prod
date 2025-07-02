import os
import json
from datetime import datetime, timedelta
from flask import Flask, render_template, request, redirect, url_for, flash
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = Flask(__name__, template_folder='app/templates')
app.secret_key = os.urandom(24)  # Secret key for flash messages

# Get the Azure Storage account details from environment variables
AZURE_STORAGE_BLOB_ENDPOINT = os.environ.get('AZURE_STORAGE_BLOB_ENDPOINT')
CONTAINER_NAME = os.environ.get('AZURE_STORAGE_CONTAINER_NAME', 'files')
STATUS_CONTAINER_NAME = 'status'  # Container for health status control
STATUS_BLOB_NAME = 'health-status.json'  # Blob name for health status

# Initialize the Azure Storage credentials and client
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(account_url=AZURE_STORAGE_BLOB_ENDPOINT, credential=credential)

def _get_status_blob():
    """Get status blob content or None if not found/error."""
    try:
        if not AZURE_STORAGE_BLOB_ENDPOINT:
            return None
            
        container_client = blob_service_client.get_container_client(STATUS_CONTAINER_NAME)
        if not container_client.exists():
            return None
        
        blob_client = container_client.get_blob_client(STATUS_BLOB_NAME)
        content = blob_client.download_blob().readall().decode('utf-8')
        return json.loads(content)
    except:
        return None

def _is_unhealthy_expired(status_data):
    """Check if unhealthy period has expired."""
    if not status_data or status_data.get('status') != 'unhealthy':
        return False
    
    expiry = status_data.get('unhealthy_until')
    if not expiry:
        return False
        
    return datetime.utcnow() > datetime.fromisoformat(expiry)

def _set_status_blob(unhealthy_seconds=0):
    """Set status blob with unhealthy duration (0 = healthy)."""
    try:
        if not AZURE_STORAGE_BLOB_ENDPOINT:
            return False
        
        container_client = blob_service_client.get_container_client(STATUS_CONTAINER_NAME)
        
        # Create container if it doesn't exist
        if not container_client.exists():
            container_client.create_container()
        
        blob_client = container_client.get_blob_client(STATUS_BLOB_NAME)
        
        now = datetime.utcnow()
        status_data = {'timestamp': now.isoformat()}
        
        if unhealthy_seconds > 0:
            status_data.update({
                'status': 'unhealthy',
                'unhealthy_until': (now + timedelta(seconds=unhealthy_seconds)).isoformat()
            })
        else:
            status_data['status'] = 'healthy'
        
        blob_client.upload_blob(json.dumps(status_data), overwrite=True)
        return True
        
    except:
        return False

@app.route('/', methods=['GET'])
def index():
    """Render the home page with the upload form."""
    region_info = {
        'region': os.environ.get('AZURE_REGION', 'unknown'),
        'region_suffix': os.environ.get('AZURE_REGION_SUFFIX', 'unknown'),
        'hostname': request.headers.get('Host', 'unknown')
    }
    
    # Get current health status for display
    status_data = _get_status_blob()
    is_healthy = True  # Default to healthy
    
    if status_data:
        if _is_unhealthy_expired(status_data):
            _set_status_blob(0)  # Reset to healthy
            is_healthy = True
        else:
            is_healthy = status_data.get('status') == 'healthy'
    
    return render_template('index.html', region_info=region_info, health_status=is_healthy)

@app.route('/upload', methods=['POST'])
def upload_file():
    """Handle the file upload from the text area."""
    if request.method == 'POST':
        # Get the filename and content from the form
        filename = request.form.get('filename')
        file_content = request.form.get('file_content')
        
        if not filename or not file_content:
            flash('Both filename and content are required.', 'error')
            return redirect(url_for('index'))
        
        try:
            # Create the container if it doesn't exist
            container_client = blob_service_client.get_container_client(CONTAINER_NAME)
            if not container_client.exists():
                container_client.create_container()
            
            # Upload the content to Azure Blob Storage
            blob_client = container_client.get_blob_client(filename)
            blob_client.upload_blob(file_content, overwrite=True)
            
            flash(f'File {filename} uploaded successfully!', 'success')
        except Exception as e:
            flash(f'Error uploading file: {str(e)}', 'error')
        
        return redirect(url_for('index'))

@app.route('/files', methods=['GET'])
def list_files():
    """List all files in the Azure Storage container."""
    try:
        # Get the container client
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        
        # List all blobs in the container
        blobs = container_client.list_blobs()
        files = [blob.name for blob in blobs]
        
        return render_template('files.html', files=files)
    except Exception as e:
        flash(f'Error listing files: {str(e)}', 'error')
        return redirect(url_for('index'))

@app.route('/files/<filename>', methods=['GET'])
def view_file(filename):
    """View the content of a file."""
    try:
        # Get the blob client
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        blob_client = container_client.get_blob_client(filename)
        
        # Download the blob
        download_stream = blob_client.download_blob()
        file_content = download_stream.readall().decode('utf-8')
        
        return render_template('view.html', filename=filename, content=file_content)
    except Exception as e:
        flash(f'Error viewing file: {str(e)}', 'error')
        return redirect(url_for('files'))

@app.route('/health/control', methods=['POST'])
def control_health():
    """Control health status endpoint."""
    action = request.form.get('action')
    
    if action == 'make_unhealthy':
        success = _set_status_blob(60)  # Unhealthy for 60 seconds
        flash('Health set to unhealthy for 60 seconds' if success else 'Failed to update health', 
              'success' if success else 'error')
    elif action == 'make_healthy':
        success = _set_status_blob(0)  # Healthy
        flash('Health set to healthy' if success else 'Failed to update health', 
              'success' if success else 'error')
    else:
        flash('Invalid action', 'error')
    
    return redirect(url_for('index'))

@app.route('/health')
def health_check():
    """Health check endpoint with optional control via query parameters."""
    # Handle control actions via query parameters (for API usage)
    action = request.args.get('action')
    if action == 'unhealthy':
        _set_status_blob(60)
    elif action == 'healthy':
        _set_status_blob(0)
    
    # Get current status
    status_data = _get_status_blob()
    is_healthy = True  # Default to healthy (fail-open)
    
    if status_data:
        if _is_unhealthy_expired(status_data):
            _set_status_blob(0)  # Auto-recover
            is_healthy = True
        else:
            is_healthy = status_data.get('status') == 'healthy'
    
    # Test storage connectivity only if we think we're healthy
    storage_healthy = is_healthy
    if is_healthy:
        try:
            blob_service_client.get_container_client(STATUS_CONTAINER_NAME).get_container_properties()
        except:
            storage_healthy = False
            is_healthy = False
    
    status_code = 200 if is_healthy else 503
    response = {
        'status': 'healthy' if is_healthy else 'unhealthy',
        'timestamp': datetime.utcnow().isoformat(),
        'services': {
            'storage': 'healthy' if storage_healthy else 'unhealthy',
            'application': 'healthy' if is_healthy else 'unhealthy'
        }
    }
    
    if status_data:
        response['blob_data'] = status_data
        
    return response, status_code

@app.route('/info')
def app_info():
    """Application info endpoint for monitoring and debugging."""
    import os
    import platform
    
    return {
        'application': 'Azure Multi-Region File App',
        'version': '1.0.0',
        'region': os.environ.get('AZURE_REGION', 'unknown'),
        'region_suffix': os.environ.get('AZURE_REGION_SUFFIX', 'unknown'),
        'environment': os.environ.get('AZURE_ENV_NAME', 'unknown'),
        'hostname': platform.node(),
        'storage_endpoint': AZURE_STORAGE_BLOB_ENDPOINT,
        'container_name': CONTAINER_NAME,
        'front_door_id': request.headers.get('X-Azure-FDID', 'direct-access'),
        'request_headers': dict(request.headers)
    }

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
