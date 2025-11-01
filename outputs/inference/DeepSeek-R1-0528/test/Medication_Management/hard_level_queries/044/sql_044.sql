WITH pe_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '415%') OR
    (icd_version = 10 AND icd_code LIKE 'I26%')
),
cohort_diag AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN pe_codes 
    ON diag.icd_code = pe_codes.icd_code 
    AND diag.icd_version = pe_codes.icd_version
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN cohort_diag d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
),
cohort_age_filtered AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 64 AND 74
),
meds AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT drug) AS med_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
  INNER JOIN cohort_age_filtered c 
    ON rx.hadm_id = c.hadm_id
  WHERE rx.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY hadm_id
),
cohort_with_meds AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(m.med_count, 0) AS med_count
  FROM cohort_age_filtered c
  LEFT JOIN meds m
    ON c.hadm_id = m.hadm_id
),
cohort_ready AS (
  SELECT 
    c.hadm_id,
    c.med_count,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los,
    c.hospital_expire_flag,
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN NULL  -- Exclude deceased
      WHEN (
        SELECT MIN(a2.admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.admittime > c.dischtime
      ) <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS readmit_30d_flag
  FROM cohort_with_meds c
),
with_tertile AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM cohort_ready
)
SELECT 
  tertile,
  COUNT(hadm_id) AS admissions,
  MIN(med_count) AS min_med_count,
  MAX(med_count) AS max_med_count,
  ROUND(AVG(los), 2) AS avg_los,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_pct,
  ROUND(100 * AVG(readmit_30d_flag), 2) AS readmission_pct
FROM with_tertile
GROUP BY tertile
ORDER BY tertile;