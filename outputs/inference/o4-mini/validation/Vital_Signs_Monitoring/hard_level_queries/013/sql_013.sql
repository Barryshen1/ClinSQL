WITH first_icus AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
),
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM first_icus f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
   AND f.hadm_id   = a.hadm_id
  WHERE
    f.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code    = diag.icd_code
       AND d.icd_version = diag.icd_version
      WHERE d.subject_id = f.subject_id
        AND d.hadm_id    = f.hadm_id
        AND LOWER(diag.long_title) LIKE '%trauma%'
    )
),
vitals_24h AS (
  SELECT
    c.stay_id,
    SUM(IF(di.label = 'Heart Rate' AND ce.valuenum > 100, 1, 0))        AS tachycardia_count,
    SUM(IF(di.label = 'Mean Arterial Pressure' AND ce.valuenum < 65, 1, 0)) AS hypotension_count,
    SUM(IF(di.label = 'Respiratory Rate' AND ce.valuenum > 20, 1, 0))       AS tachypnea_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
   AND c.hadm_id    = ce.hadm_id
   AND c.stay_id    = ce.stay_id
   AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
   AND di.label IN ('Heart Rate','Mean Arterial Pressure','Respiratory Rate')
  GROUP BY c.stay_id
),
scored AS (
  SELECT
    c.*,
    COALESCE(v.tachycardia_count,0) AS tachycardia_count,
    COALESCE(v.hypotension_count,0) AS hypotension_count,
    COALESCE(v.tachypnea_count,0)   AS tachypnea_count,
    (COALESCE(v.tachycardia_count,0)
     + COALESCE(v.hypotension_count,0)
     + COALESCE(v.tachypnea_count,0)
    ) AS instability_score
  FROM cohort c
  LEFT JOIN vitals_24h v
    ON c.stay_id = v.stay_id
),
with_quartile AS (
  SELECT
    s.*,
    NTILE(4) OVER (ORDER BY s.instability_score) AS quartile,
    PERCENTILE_CONT(s.instability_score, 0.90) OVER() AS p90
  FROM scored s
),
partA AS (
  -- Quartile summary
  SELECT
    CAST(quartile AS STRING)                     AS group_label,
    COUNT(*)                                     AS n_stays,
    AVG(instability_score)                       AS avg_instability_score,
    AVG(los)                                     AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64))   AS mortality_rate,
    NULL                                         AS mean_tachycardia_episodes,
    NULL                                         AS mean_hypotension_episodes,
    NULL                                         AS mean_tachypnea_episodes
  FROM with_quartile
  GROUP BY quartile
),
partB AS (
  -- Top-decile vital sign details
  SELECT
    'TopDecile'                                  AS group_label,
    NULL                                         AS n_stays,
    NULL                                         AS avg_instability_score,
    NULL                                         AS avg_icu_los,
    NULL                                         AS mortality_rate,
    AVG(tachycardia_count)                       AS mean_tachycardia_episodes,
    AVG(hypotension_count)                       AS mean_hypotension_episodes,
    AVG(tachypnea_count)                         AS mean_tachypnea_episodes
  FROM with_quartile
  WHERE instability_score >= p90
)
SELECT * FROM partA
UNION ALL
SELECT * FROM partB;