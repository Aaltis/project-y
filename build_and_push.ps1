# Set variables
$APP_NAME = "customer"
$DOCKER_USERNAME = "aaltis"
$IMAGE_TAG = "latest"
$DOCKER_IMAGE = "$DOCKER_USERNAME/${APP_NAME}:${IMAGE_TAG}"

# Navigate to project directory
cd "D:\Antti\Code\project-y\Customer"

# Clean and build the Spring Boot app
Write-Host "Building the Spring Boot application..."
./gradlew clean build -x test

# Build the Docker image
Write-Host "Building Docker image..."
docker build -t $DOCKER_IMAGE .

# Push the image to Docker Hub
Write-Host "Pushing image to Docker Hub..."
docker push $DOCKER_IMAGE

Write-Host "Deployment complete! Image is available at: https://hub.docker.com/r/${DOCKER_USERNAME}/${APP_NAME}"
