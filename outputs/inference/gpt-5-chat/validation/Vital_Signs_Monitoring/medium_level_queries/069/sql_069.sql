WITH female_age_filtered AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 41 AND 51
),
rr_first48 AS (
  SELECT
    f.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM female_age_filtered f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum < 80
    AND ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY f.stay_id
),
stroke_flag AS (
  SELECT
    f.stay_id,
    COUNT(*) > 0 AS stroke_flag
  FROM female_age_filtered f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  WHERE ( (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^(43[0-8])'))
       OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^(I6[0-9])')) )
  GROUP BY f.stay_id
),
merged AS (
  SELECT
    r.stay_id,
    r.mean_rr,
    CASE
      WHEN r.mean_rr < 12 THEN '<12'
      WHEN r.mean_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN r.mean_rr BETWEEN 21 AND 29 THEN '21-29'
      WHEN r.mean_rr >= 30 THEN '>=30'
    END AS rr_category,
    IFNULL(s.stroke_flag, FALSE) AS stroke_flag
  FROM rr_first48 r
  LEFT JOIN stroke_flag s
    ON r.stay_id = s.stay_id
)
SELECT
  rr_category,
  COUNT(*) AS n_stays,
  SUM(CASE WHEN stroke_flag THEN 1 ELSE 0 END) AS n_stroke,
  SAFE_DIVIDE(SUM(CASE WHEN stroke_flag THEN 1 ELSE 0 END), COUNT(*)) AS stroke_rate
FROM merged
GROUP BY rr_category
ORDER BY
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;