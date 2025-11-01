WITH
-- 1. Female inpatients aged 44-54
female_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

-- 2. Identify ICH admissions (ICD-9: 431, 432.x; ICD-10: I61.x, I62.x)
ich_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-9
      (d.icd_version = 9 AND (
        d.icd_code LIKE '431%' OR
        d.icd_code LIKE '432%'
      ))
      OR
      -- ICD-10
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I61%' OR
        d.icd_code LIKE 'I62%'
      ))
    )
),

-- 3. DRG risk scores for admissions
admission_drgs AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CAST(drg_severity AS INT64)) AS max_drg_severity,
    MAX(CAST(drg_mortality AS INT64)) AS max_drg_mortality
  FROM
    `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY
    subject_id, hadm_id
),

-- 4. Major complications: mechanical ventilation, craniotomy, sepsis, ARF
major_complications AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- Sepsis: ICD-9 99591, 99592; ICD-10 A41.x
      (d.icd_version = 9 AND (d.icd_code IN ('99591', '99592')))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'A41%')
      -- Acute renal failure: ICD-9 584.x; ICD-10 N17.x
      OR (d.icd_version = 9 AND d.icd_code LIKE '584%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
  UNION DISTINCT
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    1 AS has_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    (
      -- Mechanical ventilation: ICD-9 96.7x; ICD-10 5A1935Z, 5A1945Z, 5A1955Z
      (p.icd_version = 9 AND p.icd_code LIKE '967%')
      OR (p.icd_version = 10 AND p.icd_code IN ('5A1935Z', '5A1945Z', '5A1955Z'))
      -- Craniotomy: ICD-9 01.24, 01.25; ICD-10 00B00ZZ, 00B10ZZ
      OR (p.icd_version = 9 AND p.icd_code IN ('0124', '0125'))
      OR (p.icd_version = 10 AND p.icd_code IN ('00B00ZZ', '00B10ZZ'))
    )
),

-- 5. Combine all female inpatients with risk, complications, LOS, mortality
female_inpatients_full AS (
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.anchor_age,
    fi.gender,
    fi.admittime,
    fi.dischtime,
    fi.deathtime,
    fi.hospital_expire_flag,
    fi.dod,
    ad.max_drg_severity,
    ad.max_drg_mortality,
    TIMESTAMP_DIFF(fi.dischtime, fi.admittime, HOUR)/24.0 AS los_days,
    CASE
      WHEN mc.has_complication = 1 THEN 1 ELSE 0
    END AS major_complication,
    -- 90-day mortality: death within 90 days of admittime
    CASE
      WHEN fi.deathtime IS NOT NULL AND TIMESTAMP_DIFF(fi.deathtime, fi.admittime, DAY) <= 90 THEN 1
      WHEN fi.dod IS NOT NULL AND TIMESTAMP_DIFF(fi.dod, fi.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS mortality_90d
  FROM
    female_inpatients fi
    LEFT JOIN admission_drgs ad
      ON fi.subject_id = ad.subject_id AND fi.hadm_id = ad.hadm_id
    LEFT JOIN major_complications mc
      ON fi.subject_id = mc.subject_id AND fi.hadm_id = mc.hadm_id
),

-- 6. ICH cohort
ich_cohort AS (
  SELECT
    f.*
  FROM
    female_inpatients_full f
    JOIN ich_admissions i
      ON f.subject_id = i.subject_id AND f.hadm_id = i.hadm_id
),

-- 7. Reference cohort (all female inpatients 44-54)
ref_cohort AS (
  SELECT
    *
  FROM
    female_inpatients_full
),

-- 8. Risk percentile for ICH cohort vs reference
risk_percentiles AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.max_drg_severity,
    i.max_drg_mortality,
    -- Percentile of ICH patient's risk score among reference cohort
    PERCENT_RANK() OVER (
      ORDER BY i.max_drg_mortality
    ) AS risk_percentile
  FROM
    ich_cohort i
  WHERE
    i.max_drg_mortality IS NOT NULL
),

-- 9. Summary stats for ICH cohort
ich_summary AS (
  SELECT
    COUNT(*) AS n_ich,
    APPROX_QUANTILES(max_drg_mortality, 4)[OFFSET(2)] AS median_risk,
    APPROX_QUANTILES(max_drg_mortality, 4)[OFFSET(1)] AS q1_risk,
    APPROX_QUANTILES(max_drg_mortality, 4)[OFFSET(3)] AS q3_risk,
    ROUND(100.0 * SUM(mortality_90d)/COUNT(*),1) AS mortality_90d_pct,
    ROUND(100.0 * SUM(major_complication)/COUNT(*),1) AS major_complication_pct,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_los
  FROM
    ich_cohort
),

-- 10. Median survivor LOS for ICH cohort
ich_survivor_los AS (
  SELECT
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_survivor_los
  FROM
    ich_cohort
  WHERE
    mortality_90d = 0
),

-- 11. Summary stats for reference cohort
ref_summary AS (
  SELECT
    COUNT(*) AS n_ref,
    ROUND(100.0 * SUM(major_complication)/COUNT(*),1) AS major_complication_pct,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_los
  FROM
    ref_cohort
),

-- 12. Median survivor LOS for reference cohort
ref_survivor_los AS (
  SELECT
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_survivor_los
  FROM
    ref_cohort
  WHERE
    mortality_90d = 0
),

-- 13. Aggregate risk percentiles for ICH cohort
ich_risk_percentiles AS (
  SELECT
    ARRAY_AGG(risk_percentile ORDER BY risk_percentile) AS risk_percentiles
  FROM
    risk_percentiles
)

-- Final output
SELECT
  'ICH cohort (female, 44-54, ICH)' AS cohort,
  ich_summary.n_ich,
  ich_summary.median_risk AS median_risk_score,
  ich_summary.q1_risk AS risk_score_q1,
  ich_summary.q3_risk AS risk_score_q3,
  ich_summary.mortality_90d_pct AS mortality_90d_percent,
  ich_summary.major_complication_pct AS major_complication_percent,
  ich_survivor_los.median_survivor_los AS median_survivor_los,
  ich_risk_percentiles.risk_percentiles
FROM
  ich_summary, ich_survivor_los, ich_risk_percentiles

UNION ALL

SELECT
  'Reference cohort (female, 44-54)' AS cohort,
  ref_summary.n_ref,
  NULL AS median_risk_score,
  NULL AS risk_score_q1,
  NULL AS risk_score_q3,
  NULL AS mortality_90d_percent,
  ref_summary.major_complication_pct AS major_complication_percent,
  ref_survivor_los.median_survivor_los AS median_survivor_los,
  NULL AS risk_percentiles
FROM
  ref_summary, ref_survivor_los;