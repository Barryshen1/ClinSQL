WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
)
SELECT
  discharge_group,
  COUNTIF(los >= 7) / COUNT(*) AS proportion_7_days,
  PERCENTILE_CONT(0.14) WITHIN GROUP (ORDER BY los) AS percentile_14
FROM patient_admissions
WHERE
  gender = 'M'
  AND age_at_admission BETWEEN 64 AND 74
  AND discharge_group IN ('Home', 'SNF/rehab/LTACH', 'In-hospital death')
GROUP BY discharge_group;