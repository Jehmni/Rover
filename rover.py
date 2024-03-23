# Import necessary modules
from flask import Flask, request, jsonify  
from flask_sqlalchemy import SQLAlchemy  
import heapq   
from math import radians, sin, cos, sqrt, atan2

# Create a Flask application instance
app = Flask(__name__)   

# Configure the Flask application to use SQLite database located at 'database.db'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///database.db'

# Create an SQLAlchemy database instance
db = SQLAlchemy(app)    

# Define a database model for the 'User' table
class User(db.Model):    
    id = db.Column(db.Integer, primary_key=True)  
    username = db.Column(db.String(50), unique=True, nullable=False)  
    password = db.Column(db.String(100), nullable=False)  
    email = db.Column(db.String(100), unique=True, nullable=False)  
    events = db.relationship('EventSubscription', backref='user', lazy=True)
    pickups = db.relationship('PickupRequest', backref='user', lazy=True)

# Define a database model for the 'BusDriver' table
class BusDriver(db.Model):   # Define a class 'BusDriver' inheriting from db.Model
    # Define columns for the BusDriver table
    id = db.Column(db.Integer, primary_key=True)  # Define a column 'id' as primary key
    latitude = db.Column(db.Float, nullable=False)    # Define a column 'latitude' with float type and not nullable
    longitude = db.Column(db.Float, nullable=False)   # Define a column 'longitude' with float type and not nullable


# Define a database model for the 'Event' table
class Event(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    pickups = db.relationship('PickupRequest', backref='event', lazy=True)

# Define a database model for the 'EventSubscription' table
class EventSubscription(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)

# Define a database model for the 'PickupRequest' table
class PickupRequest(db.Model):   
    id = db.Column(db.Integer, primary_key=True)  
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)  
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)
    latitude = db.Column(db.Float, nullable=False)    
    longitude = db.Column(db.Float, nullable=False)   

# Define the route for user registration
@app.route('/api/register', methods=['POST'])
def register():
    # Retrieve JSON data from the request
    data = request.json   
    username = data.get('username')   
    password = data.get('password')   
    email = data.get('email')   

    # Validate user input
    if not username or not password or not email:
        return jsonify({'success': False, 'message': 'Please provide username, password, and email'}), 400

    # Check if username or email already exists in the database
    existing_user = User.query.filter((User.username == username) | (User.email == email)).first()
    if existing_user:
        return jsonify({'success': False, 'message': 'Username or email already exists'}), 409

    # Create a new User object
    new_user = User(username=username, password=password, email=email)
    
    # Add the new user to the database session
    db.session.add(new_user)
    
    try:
        # Commit the transaction to save the new user to the database
        db.session.commit()
        # Return a JSON response indicating successful registration
        return jsonify({'success': True, 'message': 'User registered successfully'}), 201
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating registration failed
        return jsonify({'success': False, 'message': 'Failed to register user. Please try again later'}), 500


# Define the route for user login
@app.route('/api/login', methods=['POST'])   
def login():
    # Retrieve JSON data from the request
    data = request.json   
    username = data.get('username')   
    password = data.get('password')   

    # Query the User table to validate credentials
    user = User.query.filter_by(username=username, password=password).first()  
    if user:
        return jsonify({'success': True, 'message': 'Login successful'}), 200
    else:
        return jsonify({'success': False, 'message': 'Invalid credentials'}), 401

# Define the route for scheduling a pickup
@app.route('/api/pickup', methods=['POST'])   
def schedule_pickup():
    # Retrieve JSON data from the request
    data = request.json   
    user_id = data.get('user_id')  
    event_id = data.get('event_id')   
    longitude = data.get('longitude')   
    pickup_time = data.get('pickup_time')
    
    # Retrieve all users subscribed to the event
    users = User.query.join(EventSubscription).filter(EventSubscription.event_id == event_id).all()
    
    # Retrieve driver's location
    driver_latitude = data.get('driver_latitude')   
    driver_longitude = data.get('driver_longitude')   
    
    # Calculate distances between driver and users
    user_distances = {}
    for user in users:
        user_distance = calculate_distance(driver_latitude, driver_longitude, user.latitude, user.longitude)
        user_distances[user.id] = user_distance
    
    # Sort users by distance
    sorted_users = sorted(user_distances.items(), key=lambda x: x[1])
    
    # Retrieve pickup order
    pickup_order = [user[0] for user in sorted_users]
    
    # Save pickup requests to the database
    for user_id in pickup_order:
        pickup_request = PickupRequest(user_id=user_id, event_id=event_id, latitude=users[user_id].latitude, longitude=users[user_id].longitude)   
        db.session.add(pickup_request)   
    
    db.session.commit()   

    return jsonify({'success': True, 'message': 'Pickup requests received'}), 201


def calculate_distance(lat1, lon1, lat2, lon2):
    # Radius of the Earth in kilometers
    R = 6371.0

    # Convert latitude and longitude from degrees to radians
    lat1_rad = radians(lat1)
    lon1_rad = radians(lon1)
    lat2_rad = radians(lat2)
    lon2_rad = radians(lon2)

    # Calculate the change in coordinates
    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad

    # Haversine formula
    a = sin(dlat / 2)**2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2)**2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))

    # Calculate distance
    distance = R * c

    return distance

# Run the Flask application
if __name__ == '__main__':
    with app.app_context():
        db.create_all()  
    app.run(debug=True)
