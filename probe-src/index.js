import ms from 'ms';
import { nanoid } from 'nanoid';

export function label(milliseconds) {
  return `${nanoid(6)}: ${ms(milliseconds, { long: true })}`;
}

console.log(label(90000));
