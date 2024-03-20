# Import necessary modules
from flask import Flask, request, jsonify  # Import Flask framework components for building web applications
from flask_sqlalchemy import SQLAlchemy     # Import SQLAlchemy for database management

# Create a Flask application instance
app = Flask(__name__)   # Create an instance of the Flask application

# Configure the Flask application to use SQLite database located at 'database.db'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///database.db'

# Create an SQLAlchemy database instance
db = SQLAlchemy(app)    # Create a SQLAlchemy database instance using the Flask application instance

# Define a database model for the 'User' table
class User(db.Model):    # Define a class 'User' inheriting from db.Model (base class for SQLAlchemy models)
    # Define columns for the User table
    id = db.Column(db.Integer, primary_key=True)  # Define a column 'id' as primary key
    username = db.Column(db.String(50), unique=True, nullable=False)  # Define a column 'username' with string type, unique, and not nullable
    password = db.Column(db.String(100), nullable=False)  # Define a column 'password' with string type and not nullable

# Define a database model for the 'PickupRequest' table
class PickupRequest(db.Model):   # Define a class 'PickupRequest' inheriting from db.Model
    # Define columns for the PickupRequest table
    id = db.Column(db.Integer, primary_key=True)  # Define a column 'id' as primary key
    user_id = db.Column(db.Integer, nullable=False)  # Define a column 'user_id' with integer type and not nullable
    latitude = db.Column(db.Float, nullable=False)    # Define a column 'latitude' with float type and not nullable
    longitude = db.Column(db.Float, nullable=False)   # Define a column 'longitude' with float type and not nullable

# Define the route for user registration
@app.route('/api/register', methods=['POST'])
def register():
    # Retrieve JSON data from the request
    data = request.json   # Retrieve JSON data sent in the request body
    username = data.get('username')   # Extract 'username' from the JSON data
    password = data.get('password')   # Extract 'password' from the JSON data
    email = data.get('email')   # Extract 'email' from the JSON data

    # Check if username or email already exists in the database
    existing_user = User.query.filter((User.username == username) | (User.email == email)).first()
    if existing_user:
        # Return a JSON response indicating user already exists
        return jsonify({'success': False, 'message': 'Username or email already exists'})

    # Create a new User object
    new_user = User(username=username, password=password, email=email)
    
    # Add the new user to the database session
    db.session.add(new_user)
    
    try:
        # Commit the transaction to save the new user to the database
        db.session.commit()
        # Return a JSON response indicating successful registration
        return jsonify({'success': True, 'message': 'User registered successfully'})
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating registration failed
        return jsonify({'success': False, 'message': 'Failed to register user. Please try again later'})


# Define the route for user login
@app.route('/api/login', methods=['POST'])   # Define a route '/api/login' to handle HTTP POST requests
def login():
    # Retrieve JSON data from the request
    data = request.json   # Retrieve JSON data sent in the request body
    username = data.get('username')   # Extract 'username' from the JSON data
    password = data.get('password')   # Extract 'password' from the JSON data

    # Query the User table to validate credentials
    user = User.query.filter_by(username=username, password=password).first()  # Query User table for a user with provided username and password
    if user:
        # Return a JSON response indicating successful login
        return jsonify({'success': True, 'message': 'Login successful'})   # Return JSON response indicating successful login
    else:
        # Return a JSON response indicating invalid credentials
        return jsonify({'success': False, 'message': 'Invalid credentials'})   # Return JSON response indicating invalid credentials

# Define the route for scheduling a pickup
@app.route('/api/pickup', methods=['POST'])   # Define a route '/api/pickup' to handle HTTP POST requests
def schedule_pickup():
    # Retrieve JSON data from the request
    data = request.json   # Retrieve JSON data sent in the request body
    user_id = data.get('user_id')   # Extract 'user_id' from the JSON data
    latitude = data.get('latitude')   # Extract 'latitude' from the JSON data
    longitude = data.get('longitude')   # Extract 'longitude' from the JSON data

    # Save the pickup request to the database
    pickup_request = PickupRequest(user_id=user_id, latitude=latitude, longitude=longitude)   # Create a PickupRequest object
    db.session.add(pickup_request)   # Add the PickupRequest object to the session
    db.session.commit()   # Commit the transaction to save the PickupRequest to the database

    # Return a JSON response indicating successful pickup scheduling
    return jsonify({'success': True, 'message': 'Pickup request received'})   # Return JSON response indicating successful pickup scheduling


# Run the Flask application
if __name__ == '__main__':
    # Create all database tables within the application context
    with app.app_context():
        db.create_all()   # Create all defined database tables
    # Run the Flask application in debug mode
    app.run(debug=True)   # Run the Flask application with debug mode enabled
