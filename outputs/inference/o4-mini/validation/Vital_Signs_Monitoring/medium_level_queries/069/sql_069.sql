WITH rr AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id    = icu.hadm_id
   AND ce.stay_id    = icu.stay_id
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime 
                         AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY
    ce.subject_id, ce.hadm_id, ce.stay_id
)

SELECT
  bucket,
  COUNT(*) AS total_stays,
  SUM(stroke_flag) AS stroke_count,
  ROUND(100.0 * SUM(stroke_flag) / COUNT(*), 2) AS stroke_rate_pct
FROM (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.stay_id,
    CASE
      WHEN r.avg_rr < 12         THEN '<12'
      WHEN r.avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN r.avg_rr BETWEEN 21 AND 29 THEN '21-29'
      ELSE '>=30'
    END AS bucket,
    -- Stroke flag per admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN
          `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code    = dd.icd_code
         AND d.icd_version = dd.icd_version
        WHERE
          d.subject_id = r.subject_id
          AND d.hadm_id = r.hadm_id
          AND LOWER(dd.long_title) LIKE '%stroke%'
      ) THEN 1
      ELSE 0
    END AS stroke_flag
  FROM rr r
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON r.subject_id = icu.subject_id
   AND r.hadm_id    = icu.hadm_id
   AND r.stay_id    = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON r.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
)
GROUP BY
  bucket
ORDER BY
  bucket;