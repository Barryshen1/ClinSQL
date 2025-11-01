SELECT MAX(duration_days) AS max_duration
FROM (
  SELECT
    DATE_DIFF(
      LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime),
      GREATEST(p.starttime, a.admittime),
      DAY
    ) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 84 AND 94
    AND (
      LOWER(p.drug) LIKE '%aspirin%'
      OR LOWER(p.drug) LIKE '%clopidogrel%'
      OR LOWER(p.drug) LIKE '%plavix%'
      OR LOWER(p.drug) LIKE '%ticagrelor%'
      OR LOWER(p.drug) LIKE '%brilinta%'
      OR LOWER(p.drug) LIKE '%prasugrel%'
      OR LOWER(p.drug) LIKE '%effient%'
    )
) subquery
WHERE duration_days > 0;