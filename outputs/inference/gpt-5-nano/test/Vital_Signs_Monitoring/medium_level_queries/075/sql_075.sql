WITH map_per_stay AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id,
    AVG(ch.valuenum) AS map_mean
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ch.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ch.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'Male'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND ch.charttime BETWEEN icu.intime AND icu.outtime
    AND (
      LOWER(di.label) LIKE '%mean arterial pressure%'
      OR LOWER(di.label) LIKE '%mean bp%'
      OR LOWER(di.label) LIKE '%map%'
    )
  GROUP BY icu.stay_id, icu.hadm_id, icu.subject_id
),

mapped AS (
  SELECT
    ms.stay_id,
    ms.hadm_id,
    ms.subject_id,
    ms.map_mean,
    CASE
      WHEN ms.map_mean < 65 THEN '<65'
      WHEN ms.map_mean >= 65 AND ms.map_mean < 75 THEN '65-74'
      WHEN ms.map_mean >= 75 AND ms.map_mean < 85 THEN '75-84'
      WHEN ms.map_mean >= 85 THEN '85+'
      ELSE NULL
    END AS map_bin
  FROM map_per_stay ms
  WHERE ms.map_mean IS NOT NULL
),

strokes_per_stay AS (
  SELECT icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.subject_id = d.subject_id AND icu.hadm_id = d.hadm_id
  WHERE LOWER(di.long_title) LIKE '%stroke%'
  GROUP BY icu.stay_id
)

SELECT
  m.map_bin,
  COUNT(*) AS stay_count,
  COUNT(sp.stay_id) AS stroke_count,
  SAFE_DIVIDE(COUNT(sp.stay_id), COUNT(*)) AS stroke_rate
FROM mapped AS m
LEFT JOIN strokes_per_stay AS sp
  ON m.stay_id = sp.stay_id
GROUP BY m.map_bin
ORDER BY m.map_bin;