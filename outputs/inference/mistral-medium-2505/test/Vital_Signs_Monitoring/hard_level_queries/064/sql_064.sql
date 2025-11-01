WITH
-- Get male patients aged 45-55 at ICU admission
patient_icu_stays AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year AS age_at_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` s ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year BETWEEN 45 AND 55
),

-- Identify ARF patients using ICD codes
arf_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- ICD-9 codes for ARF (584.x) or ICD-10 codes (N17.x)
    (d.icd_version = 9 AND d.icd_code LIKE '584.%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'N17.%')
),

-- Get vital signs and lab values for composite score calculation
vital_signs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    di.label AS item_label
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN
    patient_icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  WHERE
    -- Include relevant vital signs and lab values
    ce.itemid IN (
      -- Heart rate
      220045, 211,
      -- Blood pressure (MAP)
      220050, 225309, 225310, 225312,
      -- Lactate
      225664, 220621
    )
    AND ce.charttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 48 HOUR)
),

-- Calculate composite instability score (simplified example)
composite_scores AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    -- Example score calculation (would need clinical validation)
    -- This is a placeholder - actual calculation would be more complex
    SUM(
      CASE
        WHEN vs.itemid IN (220045, 211) AND vs.valuenum > 100 THEN 1 -- Tachycardia
        WHEN vs.itemid IN (220050, 225309, 225310, 225312) AND vs.valuenum < 65 THEN 1 -- Hypotension
        WHEN vs.itemid IN (225664, 220621) AND vs.valuenum > 2 THEN 1 -- Elevated lactate
        ELSE 0
      END
    ) AS composite_score
  FROM
    vital_signs vs
  GROUP BY
    vs.subject_id, vs.hadm_id, vs.stay_id
),

-- Get 95th percentile score
percentile_score AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(95)] AS p95_score
  FROM
    composite_scores
),

-- Identify top quartile patients
top_quartile AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.composite_score,
    s.*
  FROM
    composite_scores cs
  JOIN
    patient_icu_stays s ON cs.subject_id = s.subject_id AND cs.hadm_id = s.hadm_id AND cs.stay_id = s.stay_id
  CROSS JOIN
    percentile_score ps
  WHERE
    cs.composite_score >= ps.p95_score
),

-- Age-matched cohort (non-top quartile)
age_matched_cohort AS (
  SELECT
    s.*
  FROM
    patient_icu_stays s
  JOIN
    composite_scores cs ON s.subject_id = cs.subject_id AND s.hadm_id = cs.hadm_id AND s.stay_id = cs.stay_id
  CROSS JOIN
    percentile_score ps
  WHERE
    cs.composite_score < ps.p95_score
    AND s.age_at_icu_admission BETWEEN 45 AND 55
)

-- Final comparison
SELECT
  'Top Quartile' AS cohort,
  COUNT(DISTINCT tq.subject_id) AS patient_count,
  SUM(CASE WHEN EXISTS (
    SELECT 1 FROM vital_signs vs
    WHERE vs.subject_id = tq.subject_id AND vs.hadm_id = tq.hadm_id AND vs.stay_id = tq.stay_id
    AND vs.itemid IN (220050, 225309, 225310, 225312) AND vs.valuenum < 65
  ) THEN 1 ELSE 0 END) AS hypotension_count,
  SUM(CASE WHEN EXISTS (
    SELECT 1 FROM vital_signs vs
    WHERE vs.subject_id = tq.subject_id AND vs.hadm_id = tq.hadm_id AND vs.stay_id = tq.stay_id
    AND vs.itemid IN (220045, 211) AND vs.valuenum > 100
  ) THEN 1 ELSE 0 END) AS tachycardia_count,
  AVG(tq.icu_los_hours) AS avg_icu_los_hours,
  SUM(tq.hospital_expire_flag) AS mortality_count
FROM
  top_quartile tq

UNION ALL

SELECT
  'Age-Matched Cohort' AS cohort,
  COUNT(DISTINCT amc.subject_id) AS patient_count,
  SUM(CASE WHEN EXISTS (
    SELECT 1 FROM vital_signs vs
    WHERE vs.subject_id = amc.subject_id AND vs.hadm_id = amc.hadm_id AND vs.stay_id = amc.stay_id
    AND vs.itemid IN (220050, 225309, 225310, 225312) AND vs.valuenum < 65
  ) THEN 1 ELSE 0 END) AS hypotension_count,
  SUM(CASE WHEN EXISTS (
    SELECT 1 FROM vital_signs vs
    WHERE vs.subject_id = amc.subject_id AND vs.hadm_id = amc.hadm_id AND vs.stay_id = amc.stay_id
    AND vs.itemid IN (220045, 211) AND vs.valuenum > 100
  ) THEN 1 ELSE 0 END) AS tachycardia_count,
  AVG(amc.icu_los_hours) AS avg_icu_los_hours,
  SUM(amc.hospital_expire_flag) AS mortality_count
FROM
  age_matched_cohort amc;