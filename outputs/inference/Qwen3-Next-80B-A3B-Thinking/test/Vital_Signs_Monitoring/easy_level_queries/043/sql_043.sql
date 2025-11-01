WITH first_gcs AS (
  SELECT 
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE c.itemid = 223900
    AND c.valuenum IS NOT NULL
)
SELECT AVG(fg.valuenum) AS avg_gcs
FROM first_gcs fg
JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON fg.stay_id = i.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
  AND fg.rn = 1;