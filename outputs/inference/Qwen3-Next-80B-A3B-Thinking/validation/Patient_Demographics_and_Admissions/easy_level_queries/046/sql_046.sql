WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
dapt_patients AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CASE WHEN drug IN ('Aspirin', 'Acetylsalicylic Acid', 'Clopidogrel', 'Ticagrelor', 'Prasugrel') THEN drug END) AS dapt_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY hadm_id
)
SELECT
  STDDEV_POP(f.hospital_expire_flag) AS sd_mortality
FROM first_admissions f
JOIN dapt_patients d
  ON f.hadm_id = d.hadm_id
WHERE f.rn = 1
  AND d.dapt_count >= 2;