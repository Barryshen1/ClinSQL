WITH eligible AS (
  -- Base cohort: female, age 40-50, with AKI in the admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod AS patient_dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
    )
),

details AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    e.anchor_age,
    e.gender,
    e.patient_dod,
    -- comorbidity_count: number of distinct non-AKI diagnoses for this admission
    (
      SELECT COUNT(DISTINCT di.icd_code)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = e.subject_id
        AND di.hadm_id = e.hadm_id
        AND NOT (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
    ) AS comorbidity_count,
    -- ard_present: ARDS present for this admission (guarded for NULLs)
    COALESCE(
      (
        SELECT MAX(CASE WHEN UPPER(dd.long_title) LIKE '%ACUTE RESPIRATORY DISTRESS SYNDROME%' THEN 1 ELSE 0 END)
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
          ON di.icd_code = dd.icd_code
         AND di.icd_version = dd.icd_version
        WHERE di.subject_id = e.subject_id
          AND di.hadm_id = e.hadm_id
      ),
      0
    ) AS ard_present,
    -- LOS in days for this admission
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los_days,
    -- death within 30 days post-discharge
    CASE
      WHEN e.patient_dod IS NOT NULL
           AND TIMESTAMP(e.patient_dod) > e.dischtime
           AND TIMESTAMP(e.patient_dod) <= TIMESTAMP_ADD(e.dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS death_within_30d,
    -- risk_score: 5 * comorbidity_count + 50 * ard_present (guard against NULLs)
    (
      5 * (
        SELECT COUNT(DISTINCT di.icd_code)
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE di.subject_id = e.subject_id
          AND di.hadm_id = e.hadm_id
          AND NOT (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
      )
      +
      50 * COALESCE(
        (
          SELECT MAX(CASE WHEN UPPER(dd.long_title) LIKE '%ACUTE RESPIRATORY DISTRESS SYNDROME%' THEN 1 ELSE 0 END)
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
            ON di.icd_code = dd.icd_code
           AND di.icd_version = dd.icd_version
          WHERE di.subject_id = e.subject_id
            AND di.hadm_id = e.hadm_id
        ),
        0
      )
    ) AS risk_score
  FROM eligible e
),

quintiled AS (
  SELECT d.*,
         NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM details d
)

SELECT
  quintile,
  COUNT(*) AS N,
  100.0 * SUM(death_within_30d) / COUNT(*) AS post_discharge_mortality_pct,
  100.0 * SUM(ard_present) / COUNT(*) AS ard_cooccurrence_pct,
  MEDIAN(los_days) AS median_survivor_los_days
FROM quintiled
GROUP BY quintile
ORDER BY quintile;