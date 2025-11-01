WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%o2%' 
    AND LOWER(label) LIKE '%saturation%'
),

male_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),

stay_spo2 AS (
  SELECT
    ms.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM male_icustays ms
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = ms.stay_id
  JOIN spo2_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ms.intime
      AND TIMESTAMP_ADD(ms.intime, INTERVAL 48 HOUR)
  GROUP BY ms.stay_id
),

categorized_spo2 AS (
  SELECT
    stay_id,
    CASE
      WHEN avg_spo2 <  90 THEN '< 90'
      WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90–92'
      WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93–95'
      ELSE '> 95'
    END AS spo2_category
  FROM stay_spo2
),

aki_flags AS (
  SELECT DISTINCT
    icu.stay_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = icu.hadm_id
          AND (
            (d.icd_version = 9  AND d.icd_code LIKE '584%')
         OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
          )
      )
      THEN 1 ELSE 0
    END AS aki_flag
  FROM male_icustays icu
)

SELECT
  cs.spo2_category,
  COUNT(*) AS total_stays,
  SUM(af.aki_flag) AS aki_count,
  ROUND( SAFE_DIVIDE(SUM(af.aki_flag), COUNT(*)) , 3) AS aki_rate
FROM categorized_spo2 cs
JOIN aki_flags af
  ON cs.stay_id = af.stay_id
GROUP BY cs.spo2_category
ORDER BY
  CASE cs.spo2_category
    WHEN '< 90' THEN 1
    WHEN '90–92' THEN 2
    WHEN '93–95' THEN 3
    WHEN '> 95' THEN 4
  END;