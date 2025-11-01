WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 45 AND 55
),

trauma_diagnoses AS (
  SELECT DISTINCT
    c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code BETWEEN '800' AND '999')
     OR (d.icd_version = 10 AND (d.icd_code LIKE 'S%' OR d.icd_code LIKE 'T%'))
),

cohort_with_trauma AS (
  SELECT c.*
  FROM cohort c
  JOIN trauma_diagnoses td
    ON c.hadm_id = td.hadm_id
),

medication_complexity AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM cohort_with_trauma c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL '7' DAY
  GROUP BY c.hadm_id
),

readmission AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
  WHERE a1.hadm_id IN (SELECT hadm_id FROM cohort_with_trauma)
),

los AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM cohort_with_trauma)
),

all_data AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    mc.complexity_score,
    r.readmitted_30d,
    l.los_days
  FROM cohort_with_trauma c
  LEFT JOIN medication_complexity mc ON c.hadm_id = mc.hadm_id
  LEFT JOIN readmission r ON c.hadm_id = r.hadm_id
  LEFT JOIN los l ON c.hadm_id = l.hadm_id
),

tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM all_data
)

SELECT
  tertile,
  COUNT(hadm_id) AS admissions,
  AVG(complexity_score) AS mean_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(readmitted_30d) * 100 AS readmission_30d_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;