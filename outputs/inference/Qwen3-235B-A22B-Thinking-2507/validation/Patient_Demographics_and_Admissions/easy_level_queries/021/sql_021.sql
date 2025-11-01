WITH first_admissions AS (
  SELECT 
    adm.*,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    ROW_NUMBER() OVER (
      PARTITION BY adm.subject_id 
      ORDER BY adm.admittime ASC
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
),
filtered_cohort AS (
  SELECT 
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM first_admissions fa
  WHERE 
    fa.rn = 1
    AND fa.gender = 'F'
    AND (fa.anchor_age + (EXTRACT(YEAR FROM fa.admittime) - fa.anchor_year)) BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
        ON diag.icd_code = d_diag.icd_code 
        AND diag.icd_version = d_diag.icd_version
      WHERE 
        diag.hadm_id = fa.hadm_id
        AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
    )
)
SELECT 
  ROUND(
    (SUM(hospital_expire_flag) * 100.0) / COUNT(*), 
    2
  ) AS mortality_rate_percent
FROM filtered_cohort;