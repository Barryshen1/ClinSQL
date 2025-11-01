WITH vent_stays AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON icu.subject_id = pr.subject_id
   AND icu.hadm_id    = pr.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    -- ICD-9 codes 96.70–96.72 indicate invasive mechanical ventilation
    AND pr.icd_code LIKE '96.7%'
),

-- 2) Pull first 6h systolic BP measurements for those stays
sbp_events AS (
  SELECT
    ce.valuenum AS sbp
  FROM
    vent_stays vs
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON vs.subject_id = ce.subject_id
   AND vs.hadm_id    = ce.hadm_id
   AND vs.stay_id    = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%pressure%'
    AND ce.charttime BETWEEN vs.intime
                       AND TIMESTAMP_ADD(vs.intime, INTERVAL 6 HOUR)
)

-- 3) Compute Q1, Q3, and IQR
SELECT
  quantiles[OFFSET(1)] AS Q1_sbp,
  quantiles[OFFSET(3)] AS Q3_sbp,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS IQR_sbp
FROM (
  SELECT
    APPROX_QUANTILES(sbp, 4) AS quantiles
  FROM
    sbp_events
);