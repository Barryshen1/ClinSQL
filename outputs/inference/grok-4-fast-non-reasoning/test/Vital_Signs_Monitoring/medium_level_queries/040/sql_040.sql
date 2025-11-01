WITH qualifying_stays AS (
  SELECT DISTINCT icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND EXTRACT(YEAR FROM icu.intime) - pat.anchor_year = pat.anchor_age
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.stay_id = icu.stay_id
        AND ie.itemid IN (226873, 227910)
        AND ie.amount IS NOT NULL
        AND ie.starttime BETWEEN icu.intime AND icu.outtime
    )
),
stay_sbp AS (
  SELECT 
    qs.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.stay_id = qs.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = qs.stay_id
  WHERE ce.itemid IN (220045, 220179)
    AND ce.valuenum > 0
    AND ce.valueuom = 'mmHg'
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  GROUP BY qs.stay_id
  HAVING mean_sbp IS NOT NULL
)
SELECT MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM stay_sbp;