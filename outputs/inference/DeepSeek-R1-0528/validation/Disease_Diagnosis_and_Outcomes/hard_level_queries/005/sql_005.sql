WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    a.hospital_expire_flag,
    -- 30-day mortality flag (in-hospital death OR post-discharge death within 30 days)
    CASE 
      WHEN (a.deathtime IS NOT NULL AND DATE_DIFF(a.deathtime, a.admittime, DAY) <= 30) 
        OR (p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) <= 30) 
      THEN 1 
      ELSE 0 
    END AS mortality_30d,
    -- Hospital LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
    -- Survivor flag (discharged alive)
    CASE WHEN a.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS survivor,
    -- Major complication flag (mechanical ventilation OR acute kidney injury)
    CASE WHEN 
      EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        WHERE pr.subject_id = a.subject_id 
          AND pr.hadm_id = a.hadm_id
          AND (
            (pr.icd_version = 9 AND (pr.icd_code LIKE '96.7%' OR pr.icd_code IN ('96.04', '96.05')))
            OR (pr.icd_version = 10 AND pr.icd_code IN ('5A0935Z', '5A0945Z', '5A0955Z', '0BH17EZ'))
          )
      ) OR EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 
        WHERE di2.subject_id = a.subject_id 
          AND di2.hadm_id = a.hadm_id
          AND (
            (di2.icd_version = 9 AND di2.icd_code LIKE '584%')
            OR (di2.icd_version = 10 AND di2.icd_code LIKE 'N17%')
          )
      ) 
      THEN 1 ELSE 0 END AS major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
    )
)

SELECT
  -- Risk score not available in MIMIC-IV
  NULL AS median_risk_score,
  NULL AS iqr_risk_score,
  -- 30-day mortality rate (proportion)
  AVG(mortality_30d) AS thirty_day_mortality_rate,
  -- Major complication rate (proportion)
  AVG(major_complication) AS major_complication_rate,
  -- Average LOS among survivors
  AVG(CASE WHEN survivor = 1 THEN los_hospital ELSE NULL END) AS avg_los_survivors,
  -- Risk percentile not computable without risk score
  NULL AS risk_percentile
FROM cohort;