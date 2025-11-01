WITH filtered_icustays AS (
  SELECT i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND i.first_careunit IN ('Step Down Unit', 'IMC')
),
sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Systolic%'
)
SELECT STDDEV(c.valuenum) AS sbp_stddev
FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
JOIN filtered_icustays f ON c.stay_id = f.stay_id
JOIN sbp_items s ON c.itemid = s.itemid
WHERE c.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
  AND c.valuenum IS NOT NULL
  AND c.valuenum > 0;