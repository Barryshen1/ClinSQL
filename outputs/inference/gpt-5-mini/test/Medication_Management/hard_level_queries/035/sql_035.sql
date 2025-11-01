WITH
-- identify admissions that have neutropenia-related diagnosis terms
neutrop_hads AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%neutrop%' OR LOWER(di.long_title) LIKE '%neutropenic%'
),

-- identify admissions that have fever-related diagnosis terms
fever_hads AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%fever%'
),

-- eligible admissions = intersection (admissions that have both neutropenia and fever diagnoses)
eligible_hads AS (
  SELECT n.hadm_id
  FROM neutrop_hads n
  INNER JOIN fever_hads f USING (hadm_id)
),

-- cohort: female inpatients age 40-50 with the diagnosis intersection, and with valid admittime/dischtime
cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- LOS in fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN eligible_hads e
    ON a.hadm_id = e.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- medications from prescriptions within first 48 hours (joined to cohort to avoid correlated subquery)
meds_presc AS (
  SELECT
    c.hadm_id,
    LOWER(TRIM(pr.drug)) AS med
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c
    ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND LOWER(TRIM(pr.drug)) != ''
),

-- medications from pharmacy within first 48 hours
meds_pharm AS (
  SELECT
    c.hadm_id,
    LOWER(TRIM(ph.medication)) AS med
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN cohort c
    ON ph.hadm_id = c.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND ph.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND LOWER(TRIM(ph.medication)) != ''
),

-- union distinct meds per admission
meds_union AS (
  SELECT hadm_id, med FROM meds_presc
  UNION DISTINCT
  SELECT hadm_id, med FROM meds_pharm
),

-- compute medication complexity score (distinct med count) per admission
mcs_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT med) AS mcs
  FROM meds_union
  GROUP BY hadm_id
),

-- compute 30-day readmission indicator by joining subsequent admissions (non-correlated)
readmit_30d AS (
  SELECT
    c.hadm_id,
    -- if any subsequent admission exists within 30 days -> 1 else 0
    IF(COUNT(a2.hadm_id) > 0, 1, 0) AS readmit_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a2.subject_id = c.subject_id
   AND a2.admittime > c.dischtime
   AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY c.hadm_id
),

-- combine cohort with mcs and readmit flags
mcs_by_admission AS (
  SELECT
    c.*,
    COALESCE(mc.mcs, 0) AS mcs,
    COALESCE(r.readmit_30d, 0) AS readmit_30d
  FROM cohort c
  LEFT JOIN mcs_counts mc
    ON c.hadm_id = mc.hadm_id
  LEFT JOIN readmit_30d r
    ON c.hadm_id = r.hadm_id
),

-- assign quartiles by MCS (NTILE(4) over the whole cohort ordered by mcs)
ranked AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY mcs) AS mcs_quartile
  FROM mcs_by_admission
)

-- final aggregation per quartile
SELECT
  mcs_quartile,
  COUNT(DISTINCT subject_id) AS distinct_patient_count,
  COUNT(*) AS admission_count,
  ROUND(AVG(mcs), 3) AS mean_mcs,
  MIN(mcs) AS min_mcs,
  MAX(mcs) AS max_mcs,
  ROUND(AVG(los_days), 3) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  ROUND(100.0 * AVG(readmit_30d), 2) AS readmit_30d_percent
FROM ranked
GROUP BY mcs_quartile
ORDER BY mcs_quartile;