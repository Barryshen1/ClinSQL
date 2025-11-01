WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
first_admissions_filtered AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    age_at_admission
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM first_admissions
  ) 
  WHERE rn = 1 AND age_at_admission BETWEEN 48 AND 58
),
cabg_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%bypass%' OR d.long_title LIKE '%CABG%'
)
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY CAST(f.hospital_expire_flag AS FLOAT64)) AS percentile_25
FROM first_admissions_filtered f
JOIN cabg_admissions c
  ON f.hadm_id = c.hadm_id;