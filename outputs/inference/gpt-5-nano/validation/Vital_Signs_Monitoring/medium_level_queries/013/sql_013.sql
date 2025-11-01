WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE (UPPER(p.gender) = 'MALE' OR p.gender = 'Male')
    AND p.anchor_age BETWEEN 51 AND 61
),

-- 2) Compute first-48h SpO2 average per stay
spo2_vals AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    c.subject_id,
    AVG(ce.valuenum) AS spo2_avg
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND LOWER(di.label) LIKE '%spo2%'
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id, c.hadm_id, c.subject_id
),

-- 3) AKI flag per hadm_id (ischemic/acute kidney injury codes)
aki_by_hadm AS (
  SELECT
    d.hadm_id,
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '584%') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        THEN 1
        ELSE 0
      END
    ) AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  GROUP BY d.hadm_id
)

-- 4) Combine spo2, AKI flag, and bucket into final counts
SELECT
  CASE
     WHEN s.spo2_avg < 90 THEN '<90'
     WHEN s.spo2_avg >= 90 AND s.spo2_avg < 93 THEN '90-92'
     WHEN s.spo2_avg >= 93 AND s.spo2_avg < 96 THEN '93-95'
     ELSE '>95'
  END AS spo2_bin,
  COUNT(*) AS patient_count,
  AVG(COALESCE(a.aki_flag, 0)) AS aki_rate
FROM spo2_vals AS s
LEFT JOIN aki_by_hadm AS a
  ON s.hadm_id = a.hadm_id
GROUP BY spo2_bin
ORDER BY spo2_bin;