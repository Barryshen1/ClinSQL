WITH male_40_50 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 40 AND 50
),
sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE 'systolic blood pressure%'
    AND LOWER(unitname) = 'mmhg'
),
sbp_48h AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN male_40_50 p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN sbp_itemids sbp
    ON ce.itemid = sbp.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
sbp_cats AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    mean_sbp,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_cat
  FROM sbp_48h
),
mi_flags AS (
  SELECT DISTINCT
    d.hadm_id,
    1 AS mi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
)
SELECT
  sbp_cat,
  COUNT(*) AS n_stays,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_stays,
  ROUND(SUM(CASE WHEN mf.mi_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mi_rate_pct
FROM sbp_cats sc
LEFT JOIN mi_flags mf
  ON sc.hadm_id = mf.hadm_id
GROUP BY sbp_cat
ORDER BY sbp_cat;