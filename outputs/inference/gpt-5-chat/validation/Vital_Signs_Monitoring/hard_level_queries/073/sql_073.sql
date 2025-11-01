WITH patient_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 47 AND 57
    AND icu.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
    )
),

-- Example calculation of instability score from first 72 hours vital signs:
-- Placeholder: here we just take an arbitrary aggregation (sd of HR and BP)
-- Replace with your true scoring formula
score_data AS (
  SELECT
    pc.*,
    SAFE_DIVIDE(SUM(CASE WHEN ce.itemid IN (220045, 211) THEN ce.valuenum ELSE NULL END), COUNT(DISTINCT CASE WHEN ce.itemid IN (220045, 211) THEN ce.charttime END)) 
      AS instability_score
  FROM
    patient_cohort pc
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = pc.stay_id
    AND ce.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    pc.subject_id, pc.hadm_id, pc.stay_id, pc.gender, pc.anchor_age, pc.hospital_expire_flag, pc.intime, pc.outtime, pc.los
),

percentiles AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS pct_rank
  FROM score_data
),

-- Percentile value for instability_score = 75
score_75_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS score_at_75th_pct
  FROM percentiles
),

top_decile AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM percentiles
  WHERE pct_rank >= 0.9
)

SELECT
  -- Find where score 75 lies among cohort
  (SELECT
     100 * COUNTIF(instability_score <= 75) / COUNT(*)
   FROM percentiles) AS percentile_for_score_75,
  td.avg_icu_los,
  td.mortality_rate
FROM top_decile td;