WITH systolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(category) LIKE '%blood pressure%'
),
female_elderly_icustays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
),
bp_first48 AS (
  SELECT
    fe.subject_id,
    fe.hadm_id,
    fe.stay_id,
    AVG(fe.valuenum) AS mean_sysbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` fe
  JOIN female_elderly_icustays icu
    ON fe.stay_id = icu.stay_id
  JOIN systolic_bp_items sbi
    ON fe.itemid = sbi.itemid
  WHERE fe.valuenum IS NOT NULL
    AND fe.charttime >= icu.intime
    AND fe.charttime <= DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY fe.subject_id, fe.hadm_id, fe.stay_id
)
SELECT
  SAFE_DIVIDE(COUNTIF(mean_sysbp <= 140), COUNT(*)) AS percentile_140
FROM bp_first48;