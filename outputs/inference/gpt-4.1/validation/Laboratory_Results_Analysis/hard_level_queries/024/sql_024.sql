WITH
-- 1. Identify cardiac arrest ICD codes
arrest_icds AS (
  SELECT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE
    -- ICD-10 I46.x (cardiac arrest)
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I46'))
    -- ICD-9 427.5 (cardiac arrest), 427.4x (ventricular fibrillation/flutter)
    OR (icd_version = 9 AND (icd_code = '4275' OR REGEXP_CONTAINS(icd_code, r'^4274')))
),

-- 2. Female inpatients age 53–63 with post-arrest
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON adm.hadm_id = dx.hadm_id
  JOIN arrest_icds ai
    ON dx.icd_code = ai.icd_code AND dx.icd_version = ai.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),

-- 3. Lab instability score for each admission in cohort (first 48h)
cohort_lab_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(
      -- Critical lab: flagged OR out of reference range
      (le.flag IN ('abnormal', 'critical'))
      OR (SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
            OR
            (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
          )
      )
    ) AS lab_instability_score
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  WHERE
    le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

-- 4. 90th percentile of lab instability score
percentile_90 AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[90] AS p90_lab_instability
  FROM cohort_lab_instability
),

-- 5. Admissions with score >= 90th percentile
high_instability AS (
  SELECT
    cli.subject_id,
    cli.hadm_id,
    cli.lab_instability_score
  FROM cohort_lab_instability cli
  CROSS JOIN percentile_90 p
  WHERE cli.lab_instability_score >= p.p90_lab_instability
),

-- 6. Summary for high instability admissions
high_instability_summary AS (
  SELECT
    COUNT(*) AS admission_count,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0) AS mean_los_days,
    AVG(cli.lab_instability_score) AS mean_lab_instability_score
  FROM high_instability hi
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON hi.hadm_id = a.hadm_id
  JOIN cohort_lab_instability cli
    ON hi.hadm_id = cli.hadm_id
),

-- 7. Mean critical lab frequency for all inpatients (first 48h)
all_admissions_lab_instability AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNTIF(
      (le.flag IN ('abnormal', 'critical'))
      OR (SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
            OR
            (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
          )
      )
    ) AS lab_instability_score
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
  WHERE
    le.charttime >= adm.admittime
    AND le.charttime < TIMESTAMP_ADD(adm.admittime, INTERVAL 48 HOUR)
  GROUP BY adm.subject_id, adm.hadm_id
),

all_inpatients_summary AS (
  SELECT
    AVG(lab_instability_score) AS mean_lab_instability_score
  FROM all_admissions_lab_instability
)

-- Final output
SELECT
  p.p90_lab_instability AS lab_instability_score_90th_percentile,
  his.admission_count,
  his.mortality_rate,
  his.mean_los_days,
  his.mean_lab_instability_score AS mean_critical_lab_freq_high_instability,
  ais.mean_lab_instability_score AS mean_critical_lab_freq_all_inpatients
FROM percentile_90 p
CROSS JOIN high_instability_summary his
CROSS JOIN all_inpatients_summary ais;