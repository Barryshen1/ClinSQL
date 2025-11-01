WITH rrt_icustays AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    USING (subject_id)
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = icu.stay_id
        AND LOWER(pe.ordercategoryname) LIKE '%dialysis%'
    )
),
score_72h AS (
  SELECT
    rrt.stay_id,
    MAX(ce.valuenum) AS max_score_72h
  FROM rrt_icustays rrt
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON rrt.stay_id = ce.stay_id
  WHERE ce.itemid = 123456  -- TODO: replace with actual instability score itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN rrt.intime AND TIMESTAMP_ADD(rrt.intime, INTERVAL 72 HOUR)
  GROUP BY rrt.stay_id
),
distribution AS (
  SELECT
    s.*,
    rrt.hadm_id,
    rrt.subject_id,
    rrt.los,
    adm.hospital_expire_flag
  FROM score_72h s
  JOIN rrt_icustays rrt USING (stay_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON rrt.hadm_id = adm.hadm_id
),
percentile_of_85 AS (
  SELECT
    SAFE_DIVIDE(COUNTIF(max_score_72h <= 85), COUNT(*)) * 100 AS percentile_85
  FROM distribution
),
quartiles AS (
  SELECT
    d.*,
    NTILE(4) OVER (ORDER BY max_score_72h DESC) AS quartile_desc
  FROM distribution d
),
quartile_metrics AS (
  SELECT
    AVG(CASE WHEN quartile_desc = 1 THEN los END) AS avg_icu_los_most_unstable,
    AVG(CASE WHEN quartile_desc = 1 THEN hospital_expire_flag END) AS hosp_mortality_rate_most_unstable
  FROM quartiles
)
SELECT
  p.percentile_85,
  q.avg_icu_los_most_unstable,
  q.hosp_mortality_rate_most_unstable
FROM percentile_of_85 p
CROSS JOIN quartile_metrics q;