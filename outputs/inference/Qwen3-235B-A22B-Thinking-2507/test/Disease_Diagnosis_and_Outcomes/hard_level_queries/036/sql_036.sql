WITH patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
),

pneumonia_patients AS (
  SELECT DISTINCT
    poi.*
  FROM patients_of_interest poi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON poi.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND (
      d.icd_code LIKE 'J09%' OR
      d.icd_code LIKE 'J10.0%' OR
      d.icd_code LIKE 'J11.0%' OR
      d.icd_code LIKE 'J12%' OR
      d.icd_code LIKE 'J13%' OR
      d.icd_code LIKE 'J14%' OR
      d.icd_code LIKE 'J15%' OR
      d.icd_code LIKE 'J16%' OR
      d.icd_code LIKE 'J17%' OR
      d.icd_code LIKE 'J18%' OR
      d.icd_code LIKE 'J69.0%'
    )
),

comorbidity AS (
  SELECT
    pp.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM pneumonia_patients pp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pp.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND NOT (
      d.icd_code LIKE 'J09%' OR
      d.icd_code LIKE 'J10.0%' OR
      d.icd_code LIKE 'J11.0%' OR
      d.icd_code LIKE 'J12%' OR
      d.icd_code LIKE 'J13%' OR
      d.icd_code LIKE 'J14%' OR
      d.icd_code LIKE 'J15%' OR
      d.icd_code LIKE 'J16%' OR
      d.icd_code LIKE 'J17%' OR
      d.icd_code LIKE 'J18%' OR
      d.icd_code LIKE 'J69.0%'
    )
  GROUP BY pp.hadm_id
),

top_comorbidity AS (
  SELECT
    pp.*,
    c.comorbidity_count,
    NTILE(4) OVER (ORDER BY c.comorbidity_count DESC) AS comorbidity_quartile
  FROM pneumonia_patients pp
  INNER JOIN comorbidity c
    ON pp.hadm_id = c.hadm_id
),
final_cohort AS (
  SELECT *
  FROM top_comorbidity
  WHERE comorbidity_quartile = 4
),

complications AS (
  SELECT DISTINCT
    fc.hadm_id
  FROM final_cohort fc
  WHERE 
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = fc.hadm_id
        AND pe.itemid IN (225468, 225442)  -- Verified vent itemids
    )
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = fc.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'J96%')
    )
)

SELECT
  (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS complication_pct,
  APPROX_QUANTILES(
    CASE
      WHEN deathtime IS NOT NULL THEN DATETIME_DIFF(deathtime, admittime, DAY)
      ELSE DATETIME_DIFF(dischtime, admittime, DAY)
    END,
    100
  )[OFFSET(50)] AS median_survival_days
FROM final_cohort fc
LEFT JOIN complications c ON fc.hadm_id = c.hadm_id;