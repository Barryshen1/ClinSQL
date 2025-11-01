WITH cohort AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 70 AND 80
),
sbp24h AS (
  SELECT c.stay_id,
         MAX(ch.valuenum) AS max_sbp
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON c.subject_id = ch.subject_id
    AND c.stay_id = ch.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ch.itemid = di.itemid
  WHERE ch.valuenum IS NOT NULL
    AND di.label LIKE '%Systolic%'
    AND di.label LIKE '%Blood Pressure%'
    AND ch.charttime >= c.intime
    AND ch.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),
stroke_flags AS (
  SELECT DISTINCT c.stay_id,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS stroke_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON c.hadm_id = dx.hadm_id
  WHERE ( (dx.icd_version = 9 AND (
              dx.icd_code LIKE '430%' OR
              dx.icd_code LIKE '431%' OR
              dx.icd_code LIKE '433%' OR
              dx.icd_code LIKE '434%' OR
              dx.icd_code LIKE '436%' ))
       OR (dx.icd_version = 10 AND (
              dx.icd_code LIKE 'I63%' OR
              dx.icd_code LIKE 'I64%' ))
        )
  GROUP BY c.stay_id
),
sbp_cat AS (
  SELECT s.stay_id,
         CASE
           WHEN s.max_sbp < 130 THEN '<130'
           WHEN s.max_sbp BETWEEN 130 AND 139 THEN '130-139'
           WHEN s.max_sbp BETWEEN 140 AND 159 THEN '140-159'
           WHEN s.max_sbp >= 160 THEN '>=160'
         END AS sbp_category
  FROM sbp24h s
)
SELECT sc.sbp_category,
       COUNT(*) AS n_stays,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_stays,
       ROUND(100 * SUM(CASE WHEN sf.stroke_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS stroke_rate_percent
FROM sbp_cat sc
LEFT JOIN stroke_flags sf
  ON sc.stay_id = sf.stay_id
GROUP BY sc.sbp_category
ORDER BY sc.sbp_category;