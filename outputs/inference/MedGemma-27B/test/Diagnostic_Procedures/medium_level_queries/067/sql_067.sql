WITH PatientACS AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.los,
    d.icd_code AS acs_code,
    d.icd_version AS acs_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d.icd_code LIKE 'I2%' -- ACS codes (I20, I21, I22, I23, I24, I25, I27)
    AND d.seq_num = 1 -- Primary diagnosis
),
ACS_Ultrasound AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.acs_code,
    p.acs_version,
    p.los,
    COUNT(DISTINCT pe.itemid) AS ultrasound_count
  FROM PatientACS AS p
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON p.subject_id = pe.subject_id
    AND p.hadm_id = pe.hadm_id
  WHERE
    pe.itemid IN (
      -- Ultrasound itemids (including echo)
      -- This list might need refinement based on specific definitions
      SELECT
        itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label LIKE '%ultrasound%' OR label LIKE '%echo%'
    )
  GROUP BY
    p.subject_id,
    p.hadm_id,
    p.acs_code,
    p.acs_version,
    p.los
),
ACS_Ultrasound_Stratified AS (
  SELECT
    subject_id,
    hadm_id,
    acs_code,
    acs_version,
    los,
    ultrasound_count,
    CASE
      WHEN los BETWEEN 1 AND 4
      THEN '1-4 days'
      WHEN los BETWEEN 5 AND 7
      THEN '5-7 days'
      ELSE 'Other'
    END AS los_group,
    CASE
      WHEN acs_code LIKE 'I21%' -- STEMI
      THEN 'Primary ACS'
      WHEN acs_code LIKE 'I20%' -- UA/NSTEMI
      THEN 'Secondary ACS'
      ELSE 'Other ACS'
    END AS acs_type
  FROM ACS_Ultrasound
)
SELECT
  los_group,
  acs_type,
  PERCENTILE_CONT(0.25, ultrasound_count) AS p25,
  PERCENTILE_CONT(0.50, ultrasound_count) AS p50,
  PERCENTILE_CONT(0.75, ultrasound_count) AS p75
FROM ACS_Ultrasound_Stratified
GROUP BY
  los_group,
  acs_type
ORDER BY
  los_group,
  acs_type;