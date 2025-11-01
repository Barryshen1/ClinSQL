WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS adm_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (d.icd_code = 'A419' AND d.icd_version = 10) OR
      (d.icd_code = 'R6520' AND d.icd_version = 10)
    )
    AND a.subject_id NOT IN (
      -- Exclude patients with septic shock diagnosis
      SELECT DISTINCT a2.subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
        ON a2.hadm_id = diag2.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
        ON diag2.icd_code = d2.icd_code AND diag2.icd_version = d2.icd_version
      WHERE (d2.icd_code = 'R6521' AND d2.icd_version = 10)
         OR LOWER(d2.long_title) LIKE '%septic shock%'
    )
),
first_sepsis_adm AS (
  SELECT *
  FROM sepsis_admissions
  WHERE adm_seq = 1
),
comorbidity_flags AS (
  SELECT
    fsa.*,
    -- Check if patient has CKD in any admission
    MAX(CASE WHEN d.long_title LIKE '%chronic kidney disease%' OR d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    -- Check if patient has diabetes in any admission
    MAX(CASE WHEN d.long_title LIKE '%diabetes%' 
              AND (d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E13%') THEN 1 ELSE 0 END) AS has_diabetes
  FROM first_sepsis_adm fsa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_all
    ON fsa.subject_id = diag_all.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag_all.icd_code = d.icd_code AND diag_all.icd_version = d.icd_version
  GROUP BY fsa.subject_id, fsa.hadm_id, fsa.admittime, fsa.dischtime, fsa.hospital_expire_flag, fsa.los_days, fsa.adm_seq
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM comorbidity_flags
)
SELECT
  los_quartile,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(has_ckd) AS ckd_prevalence,
  AVG(has_diabetes) AS diabetes_prevalence
FROM quartiles
GROUP BY los_quartile
ORDER BY los_quartile;