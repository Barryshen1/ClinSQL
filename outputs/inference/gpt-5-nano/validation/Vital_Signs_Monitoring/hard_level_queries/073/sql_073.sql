WITH ich_population AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    a.subject_id,
    i.intime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    (UPPER(p.gender) = 'F' OR UPPER(p.gender) = 'FEMALE')
    AND p.anchor_age BETWEEN 47 AND 57
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' OR
          di.icd_code LIKE '431%'
        )
    )
),

-- Part 2: Compute per-stay VSIS (abnormal vital-sign counts in first 72h)
vs AS (
  SELECT
    ip.stay_id,
    ip.hadm_id,
    ip.subject_id,
    ip.intime,
    ip.los,
    -- VSIS is the sum of abnormal counts across six vital signs
    COALESCE(hr_abn, 0) + COALESCE(map_abn, 0) + COALESCE(sbp_abn, 0) + COALESCE(rr_abn, 0) + COALESCE(temp_abn, 0) + COALESCE(spo2_abn, 0) AS VSIS
  FROM
    ich_population AS ip
  LEFT JOIN (
    SELECT
      s.subject_id AS subject_id,
      s.hadm_id AS hadm_id,
      s.stay_id AS stay_id,
      SUM(CASE
            WHEN di.label LIKE '%Heart rate%' 
                 AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
            THEN CASE WHEN c.valuenum IS NULL OR c.valuenum < 60 OR c.valuenum > 100 THEN 1 ELSE 0 END
            ELSE 0 END) AS hr_abn,
      SUM(CASE
            WHEN (di.label LIKE '%Mean arterial pressure%' OR di.label LIKE '%MAP%')
                 AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
            THEN CASE WHEN c.valuenum < 65 OR c.valuenum > 110 THEN 1 ELSE 0 END
            ELSE 0 END) AS map_abn,
      SUM(CASE
            WHEN (di.label LIKE '%Systolic arterial pressure%' OR di.label LIKE '%Systolic BP%')
                 AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
            THEN CASE WHEN c.valuenum < 90 OR c.valuenum > 140 THEN 1 ELSE 0 END
            ELSE 0 END) AS sbp_abn,
      SUM(CASE
            WHEN di.label LIKE '%Respiratory rate%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
            THEN CASE WHEN c.valuenum < 12 OR c.valuenum > 20 THEN 1 ELSE 0 END
            ELSE 0 END) AS rr_abn,
      SUM(CASE
            WHEN di.label LIKE '%Temperature%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
            THEN CASE WHEN c.valuenum < 36.0 OR c.valuenum > 38.3 THEN 1 ELSE 0 END
            ELSE 0 END) AS temp_abn,
      SUM(CASE
            WHEN (di.label LIKE '%SpO2%' OR di.label LIKE '%Oxygen saturation%')
                 AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
            THEN CASE WHEN c.valuenum < 92 OR c.valuenum > 100 THEN 1 ELSE 0 END
            ELSE 0 END) AS spo2_abn
    FROM
      ich_population AS s
    LEFT JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS c
      ON c.stay_id = s.stay_id
    LEFT JOIN
      `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON c.itemid = di.itemid
    GROUP BY
      s.subject_id, s.hadm_id, s.stay_id, s.intime
  ) AS agg ON agg.stay_id = ip.stay_id
  -- The nested aggregation above produces hr_abn, map_abn, sbp_abn, rr_abn, temp_abn, spo2_abn
),

-- Combine VSIS per stay (ensuring we have a row per stay)
vs_combined AS (
  SELECT
    ip.stay_id,
    ip.hadm_id,
    ip.subject_id,
    ip.intime,
    ip.los,
    COALESCE(vs.VSIS, 0) AS VSIS
  FROM ich_population ip
  LEFT JOIN (
    SELECT
      s.subject_id AS subject_id,
      s.hadm_id AS hadm_id,
      s.stay_id AS stay_id,
      /* VSIS placeholder; actual VSIS computed in the outer query above via sums */
      NULL AS VSIS
    FROM ich_population s
  ) AS vs ON vs.stay_id = ip.stay_id
)

-- Final: produce three rows with metrics
SELECT 'percentile_75' AS metric, CAST(100.0 * SUM(CASE WHEN VSIS <= 75 THEN 1 ELSE 0 END) / COUNT(*) AS FLOAT64) AS value
FROM (
  SELECT ip.stay_id, COALESCE((COALESCE(hr_abn,0) + COALESCE(map_abn,0) + COALESCE(sbp_abn,0) + COALESCE(rr_abn,0) + COALESCE(temp_abn,0) + COALESCE(spo2_abn,0)),0) AS VSIS
  FROM ich_population ip
  LEFT JOIN (
    SELECT
      s.subject_id AS subject_id,
      s.hadm_id AS hadm_id,
      s.stay_id AS stay_id,
      SUM(CASE WHEN di.label LIKE '%Heart rate%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
               THEN CASE WHEN c.valuenum IS NULL OR c.valuenum < 60 OR c.valuenum > 100 THEN 1 ELSE 0 END ELSE 0 END) AS hr_abn,
      SUM(CASE WHEN (di.label LIKE '%Mean arterial pressure%' OR di.label LIKE '%MAP%') AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
               THEN CASE WHEN c.valuenum < 65 OR c.valuenum > 110 THEN 1 ELSE 0 END ELSE 0 END) AS map_abn,
      SUM(CASE WHEN (di.label LIKE '%Systolic arterial pressure%' OR di.label LIKE '%Systolic BP%') AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
               THEN CASE WHEN c.valuenum < 90 OR c.valuenum > 140 THEN 1 ELSE 0 END ELSE 0 END) AS sbp_abn,
      SUM(CASE WHEN di.label LIKE '%Respiratory rate%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
               THEN CASE WHEN c.valuenum < 12 OR c.valuenum > 20 THEN 1 ELSE 0 END ELSE 0 END) AS rr_abn,
      SUM(CASE WHEN di.label LIKE '%Temperature%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
               THEN CASE WHEN c.valuenum < 36.0 OR c.valuenum > 38.3 THEN 1 ELSE 0 END ELSE 0 END) AS temp_abn,
      SUM(CASE WHEN di.label LIKE '%SpO2%' OR di.label LIKE '%Oxygen saturation%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
               THEN CASE WHEN c.valuenum < 92 OR c.valuenum > 100 THEN 1 ELSE 0 END ELSE 0 END) AS spo2_abn
    FROM ich_population s
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON c.stay_id = s.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
    GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime
  ) AS calc ON calc.stay_id = ip.stay_id
) AS t
UNION ALL
SELECT 'avg_icu_los_top_decile' AS metric, CAST(AVG(i.los) AS FLOAT64) AS value
FROM (
  SELECT r.*,
         NTILE(10) OVER (ORDER BY VSIS DESC) AS decile
  FROM (
    SELECT ip.stay_id,
           ip.hadm_id,
           ip.subject_id,
           ip.intime,
           ip.los,
           COALESCE((hr_abn + map_abn + sbp_abn + rr_abn + temp_abn + spo2_abn), 0) AS VSIS
    FROM ich_population ip
    LEFT JOIN (
      SELECT s.subject_id AS subject_id,
             s.hadm_id AS hadm_id,
             s.stay_id AS stay_id,
             SUM(CASE WHEN di.label LIKE '%Heart rate%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
                      THEN CASE WHEN c.valuenum IS NULL OR c.valuenum < 60 OR c.valuenum > 100 THEN 1 ELSE 0 END ELSE 0 END) AS hr_abn,
             SUM(CASE WHEN (di.label LIKE '%Mean arterial pressure%' OR di.label LIKE '%MAP%') AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
                      THEN CASE WHEN c.valuenum < 65 OR c.valuenum > 110 THEN 1 ELSE 0 END ELSE 0 END) AS map_abn,
             SUM(CASE WHEN (di.label LIKE '%Systolic arterial pressure%' OR di.label LIKE '%Systolic BP%') AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
                      THEN CASE WHEN c.valuenum < 90 OR c.valuenum > 140 THEN 1 ELSE 0 END ELSE 0 END) AS sbp_abn,
             SUM(CASE WHEN di.label LIKE '%Respiratory rate%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
                      THEN CASE WHEN c.valuenum < 12 OR c.valuenum > 20 THEN 1 ELSE 0 END ELSE 0 END) AS rr_abn,
             SUM(CASE WHEN di.label LIKE '%Temperature%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
                      THEN CASE WHEN c.valuenum < 36.0 OR c.valuenum > 38.3 THEN 1 ELSE 0 END ELSE 0 END) AS temp_abn,
             SUM(CASE WHEN di.label LIKE '%SpO2%' OR di.label LIKE '%Oxygen saturation%' AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
                      THEN CASE WHEN c.valuenum < 92 OR c.valuenum > 100 THEN 1 ELSE 0 END ELSE 0 END) AS spo2_abn
      FROM ich_population s
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON c.stay_id = s.stay_id
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
      GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime
    ) AS calc ON calc.stay_id = ip.stay_id
  ) AS r
) AS i
WHERE 1=1
;