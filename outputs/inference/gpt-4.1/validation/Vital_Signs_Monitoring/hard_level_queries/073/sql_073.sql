WITH ich_icd_codes AS (
  -- List of ICD codes for ICH (ICD-9 and ICD-10)
  SELECT '430' AS icd_code UNION ALL
  SELECT '431' UNION ALL
  SELECT '4320' UNION ALL
  SELECT '4321' UNION ALL
  SELECT '4329' UNION ALL
  SELECT 'I60' UNION ALL
  SELECT 'I601' UNION ALL
  SELECT 'I602' UNION ALL
  SELECT 'I603' UNION ALL
  SELECT 'I604' UNION ALL
  SELECT 'I605' UNION ALL
  SELECT 'I606' UNION ALL
  SELECT 'I607' UNION ALL
  SELECT 'I608' UNION ALL
  SELECT 'I609' UNION ALL
  SELECT 'I61' UNION ALL
  SELECT 'I610' UNION ALL
  SELECT 'I611' UNION ALL
  SELECT 'I612' UNION ALL
  SELECT 'I613' UNION ALL
  SELECT 'I614' UNION ALL
  SELECT 'I615' UNION ALL
  SELECT 'I616' UNION ALL
  SELECT 'I618' UNION ALL
  SELECT 'I619' UNION ALL
  SELECT 'I62' UNION ALL
  SELECT 'I620' UNION ALL
  SELECT 'I621' UNION ALL
  SELECT 'I629'
),
vital_sign_items AS (
  -- Itemids for vital signs (from d_items)
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'heart rate', 'hr',
    'systolic blood pressure', 'sbp',
    'diastolic blood pressure', 'dbp',
    'mean blood pressure', 'mbp',
    'respiratory rate', 'rr',
    'temperature', 'temp',
    'spo2', 'o2 saturation', 'oxygen saturation'
  )
),
cohort AS (
  -- Female ICU patients aged 47–57 with ICH
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 47 AND 57
    AND (
      diag.icd_code IN (SELECT icd_code FROM ich_icd_codes)
      OR LEFT(diag.icd_code,3) IN (SELECT icd_code FROM ich_icd_codes) -- for codes like 'I60', 'I61', etc.
    )
),
vital_instability AS (
  -- For each ICU stay, count abnormal vital sign measurements in first 72h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNTIF(
      vs.label IN ('heart rate','hr') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 50 OR ce.valuenum > 120)
    ) AS hr_abn,
    COUNTIF(
      vs.label IN ('systolic blood pressure','sbp') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 90 OR ce.valuenum > 180)
    ) AS sbp_abn,
    COUNTIF(
      vs.label IN ('respiratory rate','rr') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 8 OR ce.valuenum > 30)
    ) AS rr_abn,
    COUNTIF(
      vs.label IN ('temperature','temp') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 35 OR ce.valuenum > 38.5)
    ) AS temp_abn,
    COUNTIF(
      vs.label IN ('spo2','o2 saturation','oxygen saturation') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 92)
    ) AS spo2_abn,
    COUNTIF(
      vs.label IN ('mean blood pressure','mbp') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 65 OR ce.valuenum > 120)
    ) AS mbp_abn,
    COUNTIF(
      vs.label IN ('diastolic blood pressure','dbp') AND ce.valuenum IS NOT NULL AND (ce.valuenum < 50 OR ce.valuenum > 110)
    ) AS dbp_abn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  JOIN vital_sign_items vs
    ON ce.itemid = vs.itemid
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
instability_scores AS (
  -- Sum up all abnormal counts for each stay
  SELECT
    vi.subject_id,
    vi.hadm_id,
    vi.stay_id,
    (hr_abn + sbp_abn + rr_abn + temp_abn + spo2_abn + mbp_abn + dbp_abn) AS instability_score
  FROM vital_instability vi
),
final_cohort AS (
  -- Merge instability scores with cohort info
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    s.instability_score
  FROM cohort c
  JOIN instability_scores s
    ON c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
),
percentile_calc AS (
  -- Calculate percentile for score=75
  SELECT
    COUNTIF(instability_score < 75) AS below_75,
    COUNT(*) AS total,
    SAFE_DIVIDE(COUNTIF(instability_score < 75), COUNT(*)) * 100 AS percentile_75
  FROM final_cohort
),
top_decile AS (
  -- Find the cutoff for top 10%
  SELECT
    APPROX_QUANTILES(instability_score, 10)[OFFSET(9)] AS decile_cutoff
  FROM final_cohort
),
top_decile_stats AS (
  -- Stats for top decile
  SELECT
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM final_cohort, top_decile
  WHERE instability_score >= top_decile.decile_cutoff
)
SELECT
  p.percentile_75 AS percentile_for_score_75,
  t.avg_los AS avg_icu_los_top_decile,
  t.mortality_rate AS mortality_top_decile
FROM percentile_calc p
CROSS JOIN top_decile_stats t;