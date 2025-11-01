WITH cohort AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  USING
    (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON
    p.subject_id = adm.subject_id
    AND icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = adm.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '431')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
        )
    )
),

vital_signs AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COUNT(*) AS instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND di.category = 'Vital Signs'
    AND (
      di.label LIKE '%Heart Rate%'
      OR di.label LIKE '%SBP%'
      OR di.label LIKE '%Temperature%'
      OR di.label LIKE '%RR%'
      OR di.label LIKE '%Respiratory Rate%'
      OR di.label LIKE '%GCS%'
    )
    AND (ce.warning = 1 OR ce.valuenum NOT BETWEEN COALESCE(di.lownormalvalue, -99999) AND COALESCE(di.highnormalvalue, 99999))
  GROUP BY
    c.stay_id, c.los, c.hospital_expire_flag
),

score_percentiles AS (
  SELECT
    stay_id,
    instability_score,
    los,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_rank
  FROM
    vital_signs
),

target_percentile AS (
  SELECT
    MAX(percentile_rank) AS percentile_of_75
  FROM
    score_percentiles
  WHERE
    instability_score = 75
),

top_decile AS (
  SELECT
    *
  FROM
    score_percentiles
  WHERE
    percentile_rank >= 90
)

SELECT
  (SELECT percentile_of_75 FROM target_percentile) AS percentile_of_score_75,
  AVG(los) AS avg_los_top_decile,
  AVG(hospital_expire_flag) AS mortality_top_decile
FROM
  top_decile;