WITH cabg_procs AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '36.1%')
     OR (icd_version = 10 AND icd_code LIKE '021%')
),
first_cabg AS (
  SELECT c.subject_id, a.hadm_id, a.admittime,
         ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY a.admittime) AS rn
  FROM cabg_procs c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
  QUALIFY rn = 1
),
qualified AS (
  SELECT fc.subject_id, fc.hadm_id, fc.admittime,
         p.gender,
         p.anchor_age + EXTRACT(YEAR FROM fc.admittime) - p.anchor_year AS age
  FROM first_cabg fc
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fc.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM fc.admittime) - p.anchor_year) BETWEEN 74 AND 84
)
SELECT AVG(total_los) AS mean_icu_los_days
FROM (
  SELECT q.hadm_id, SUM(ic.los) AS total_los
  FROM qualified q
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON q.hadm_id = ic.hadm_id
  GROUP BY q.hadm_id
);