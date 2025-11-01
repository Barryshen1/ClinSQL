WITH selected_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(i.first_careunit) LIKE '%step%' 
    AND LOWER(i.first_careunit) LIKE '%imc%'
)

SELECT
  s.subject_id,
  s.hadm_id,
  s.stay_id,
  STDDEV_SAMP(c.valuenum) AS sd_sbp,
  COUNT(*) AS n_measurements
FROM selected_stays AS s
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  ON c.subject_id = s.subject_id
 AND c.hadm_id = s.hadm_id
 AND c.stay_id = s.stay_id
 AND c.charttime >= s.intime
 AND c.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON di.itemid = c.itemid
WHERE (
  (LOWER(di.label) LIKE '%systolic%' AND LOWER(di.label) LIKE '%blood%pressure%')
  OR LOWER(di.label) LIKE '%systolic%bp%'
  OR LOWER(di.label) LIKE '%bp% systolic%'
)
  AND c.valuenum IS NOT NULL
GROUP BY s.subject_id, s.hadm_id, s.stay_id
ORDER BY s.subject_id, s.hadm_id, s.stay_id;