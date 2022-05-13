First, copy template and update your config.
Then use `cd your_source_dir; ./docker-build.sh [--use-current-branch --skip-latest] tag_name build/push full_image_name [docker_file_name]`.

If not passing docker_file_name, will use default --- "Dockerfile"

