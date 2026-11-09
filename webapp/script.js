const filters = document.querySelectorAll('.filter');
const pins = document.querySelectorAll('.pin');
filters.forEach(button => button.addEventListener('click', () => {
  filters.forEach(item => item.classList.remove('active'));
  button.classList.add('active');
  const selected = button.dataset.filter;
  pins.forEach(pin => {
    pin.style.display = selected === 'all' || pin.dataset.category === selected ? '' : 'none';
  });
}));
document.querySelectorAll('.save').forEach(button => button.addEventListener('click', () => {
  button.classList.toggle('saved');
  button.textContent = button.classList.contains('saved') ? '♥' : '♡';
  button.setAttribute('aria-label', button.classList.contains('saved') ? 'Unsave pin' : 'Save pin');
}));
const notes = [
  "Git it, Girl!!!.",
  "A quiet day is still a life being lived.",
  "To find yourself, think for yourself.",
  "You don't need a special occasion to use the nice things.",
  "Progress can look like trying again, gently.",
  "You are allowed to be both a masterpiece and a work in progress simultaneously.",
  "The best way to predict the future is to create it.",
  "You are not a drop in the ocean. You are the entire ocean in a drop.",
  "The only way to do great work is to love what you do.",
  "Happiness is not something ready made. It comes from your own actions.",
  "Believe you can and you're halfway there.",
  "Do what you can, with what you have, where you are.",
  "In the middle of every difficulty lies opportunity.",
  "The only limit to our realization of tomorrow will be our doubts of today.",
  "It does not matter how slowly you go as long as you do not stop."

];
document.getElementById('noteButton').addEventListener('click', () => {
  const output = document.getElementById('noteOutput');
  const current = output.dataset.index ? Number(output.dataset.index) : -1;
  const next = (current + 1) % notes.length;
  output.dataset.index = next;
  output.textContent = `“${notes[next]}”`;
});
