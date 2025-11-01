with hepatic_flag AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcode
    ON dcode.icd_code = di.icd_code AND dcode.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND (CASE
           WHEN p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL
             THEN p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
           ELSE NULL
         END) BETWEEN 80 AND 90
),

hepatic_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM hepatic_flag hf
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
),

-- 7-day Medication Complexity Score (MCS7) per admission
mcs_by_admit AS (
  SELECT hc.subject_id, hc.hadm_id,
         COALESCE(SUM(
           1.0
           + 0.5 *
             IF(LOWER(p.route) IN ('iv','intravenous','intravenous push','intravenous infusion'), 2.0,
             IF(LOWER(p.route) IN ('im','intramuscular'), 1.8,
             IF(LOWER(p.route) IN ('po','oral','by mouth','orally'), 1.0,
             IF(LOWER(p.route) LIKE '%inhal%', 1.2, 1.0))))
           )
           + 0.3 * LOG(1 + IFNULL(CAST(p.doses_per_24_hrs AS FLOAT64), 0))
           + 0.2 * LOG(1 + IFNULL(CAST(p.dose_val_rx AS FLOAT64), 0))
         ), 0) AS mcs7
  FROM hepatic_cohort hc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = hc.subject_id
   AND p.hadm_id = hc.hadm_id
   AND p.starttime BETWEEN hc.admittime AND TIMESTAMP_ADD(hc.admittime, INTERVAL 6 DAY)
  GROUP BY hc.subject_id, hc.hadm_id
),

-- Attach tertile based on MCS7
mcs_by_admit_with_tertile AS (
  SELECT m.subject_id, m.hadm_id, m.mcs7,
         NTILE(3) OVER (ORDER BY m.mcs7 ASC) AS tertile
  FROM mcs_by_admit AS m
),

-- 30-day readmission flag for hepatic admissions
readmit AS (
  SELECT hc.subject_id, hc.hadm_id,
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
           WHERE a2.subject_id = hc.subject_id
             AND a2.admittime > hc.dischtime
             AND a2.admittime <= TIMESTAMP_ADD(hc.dischtime, INTERVAL 30 DAY)
         ) THEN 1 ELSE 0 END AS readmit30
  FROM hepatic_cohort hc
),

-- Combine metrics per admission
admit_with_metrics AS (
  SELECT t.tertile,
         a.subject_id,
         a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
         CASE WHEN a.hospital_expire_flag THEN 1 ELSE 0 END AS in_hosp_mortality_flag,
         r.readmit30
  FROM hepatic_cohort a
  JOIN mcs_by_admit_with_tertile t
    ON t.subject_id = a.subject_id
   AND t.hadm_id = a.hadm_id
  LEFT JOIN readmit r
    ON r.subject_id = a.subject_id
   AND r.hadm_id = a.hadm_id
)

SELECT
  tertile,
  COUNT(*) AS n_admissions,
  AVG(los_days) AS mean_los_days,
  AVG(in_hosp_mortality_flag) AS in_hosp_mortality_rate,
  AVG(readmit30) AS readmission_rate
FROM admit_with_metrics
GROUP BY tertile
ORDER BY tertile;