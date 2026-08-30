# Contributing

Thank you for taking the time to contribute!

These guidelines help streamline the contribution process for everyone involved. By following them, you'll make it easier to review your work and collaborate effectively.

You can contribute in many ways: writing code, improving documentation, reporting bugs, requesting features, or creating tutorials. Every contribution, large or small, helps make OpenFlow Voice better.

## Table of Contents

- [Contributing Code](#contributing-code)
  - [Before You Start](#before-you-start)
  - [Setting Up Your Environment](#setting-up-your-environment)
  - [Making Changes](#making-changes)
  - [Pull Requests](#pull-requests)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Getting Help](#getting-help)

## Contributing Code

### Before You Start

- **Check existing issues**: Before creating a new issue or starting work, search existing issues to avoid duplicates.
- **Discuss major changes**: For significant features or architectural changes, please open an issue first to discuss your approach.

> [!IMPORTANT]
> All code contributions must be based on the `main` branch.

### Setting Up Your Environment

1. **Fork the repository**: Click the "Fork" button at the top of the repository page to create your own copy.

2. **Clone your fork**:
   ```bash
   git clone https://github.com/{your-username}/openflow-voice.git
   cd openflow-voice
   ```
   Replace `{your-username}` with your GitHub username.

3. **Open the project**:
   ```bash
   open OpenFlowVoice/OpenFlowVoice.xcodeproj
   ```

4. **Create a new feature branch**:
   ```bash
   git checkout -b feature/{your-feature-name}
   ```
   Use lowercase letters, numbers, and hyphens only (e.g., `feature/custom-wake-word` or `fix/hud-flicker`).

### Making Changes

1. **Make your changes**: Implement your feature or bug fix. Write clean, well-structured Swift code following the patterns already in the project.

2. **Test your changes**: Ensure your changes work as expected and don't break existing functionality. Test both Apple Speech and Parakeet engines if your change touches transcription.

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add descriptive commit message"
   ```
   Write clear, concise commit messages that explain what your changes do and why.

4. **Keep your branch up to date**:
   Regularly sync your branch with the latest changes from `main` to avoid conflicts.

5. **Push to your fork**:
   ```bash
   git push origin feature/{your-feature-name}
   ```

### Pull Requests

1. **Create a pull request**: Go to the original repository and click "New Pull Request." Select your feature branch and set the base branch to `main`.

2. **Write a detailed description**: Your PR should include:
   - A clear title summarizing the changes
   - A detailed description of what was changed and why
   - Reference to any related issues (e.g., "Fixes #123" or "Relates to #456")
   - Screenshots or screen recordings for UI or HUD changes

3. **Respond to feedback**: Maintainers may request changes. Please address them promptly.

4. **Be patient**: Reviews take time. Maintainers will get to your PR as soon as they can.

## Reporting Bugs

When reporting bugs, please include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs. actual behavior
- Which transcription engine you were using (Apple Speech or Parakeet)
- Screenshots, recordings, or Console logs if applicable
- Your environment details (macOS version, app version, Mac model)

## Feature Requests

Feature requests are welcome! Please:

- Check if the feature has already been requested
- Clearly describe the feature and its use case
- Explain why this feature would be valuable for a dictation workflow
- Be open to discussion and alternative approaches

## Getting Help

If you need help or have questions:

- Check the project documentation (see `CODEBASE_NOTES.md`)
- Search existing issues for similar questions
- Open a new issue with the "question" label

---

Thank you for contributing to OpenFlow Voice! Your efforts help make this project better for everyone.
