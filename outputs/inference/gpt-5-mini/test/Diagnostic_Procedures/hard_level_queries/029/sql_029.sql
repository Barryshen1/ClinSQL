WITH
-- 1) Identify ICU stays for male patients age 68-78
icu_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id AND icu.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- 2) Keep only those ICU stays with at least one vasopressor prescription within 72 hours of icu.intime
vaso_cohort AS (
  SELECT DISTINCT ib.*
  FROM icu_base ib
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id = ib.hadm_id
      AND pr.subject_id = ib.subject_id
      AND pr.starttime IS NOT NULL
      AND pr.starttime BETWEEN ib.intime AND TIMESTAMP_ADD(ib.intime, INTERVAL 72 HOUR)
      AND (
           LOWER(pr.drug) LIKE '%norepinephrine%'
        OR LOWER(pr.drug) LIKE '%levophed%'
        OR LOWER(pr.drug) LIKE '%epinephrine%'
        OR LOWER(pr.drug) LIKE '%adrenaline%'
        OR LOWER(pr.drug) LIKE '%phenylephrine%'
        OR LOWER(pr.drug) LIKE '%vasopressin%'
        OR LOWER(pr.drug) LIKE '%dopamine%'
        OR LOWER(pr.drug) LIKE '%dobutamine%'
      )
  )
),

-- 3) Count labs in first 72 hours after icu.intime
lab_counts AS (
  SELECT
    vc.stay_id,
    COUNT(le.labevent_id) AS lab_count
  FROM vaso_cohort vc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = vc.hadm_id
    AND le.subject_id = vc.subject_id
    AND le.charttime BETWEEN vc.intime AND TIMESTAMP_ADD(vc.intime, INTERVAL 72 HOUR)
  GROUP BY vc.stay_id
),

-- 4) Count imaging (hcpcs) in approx first 72 hours (chartdate is DATE only)
imaging_counts AS (
  SELECT
    vc.stay_id,
    COUNT(hc.chartdate) AS imaging_count
  FROM vaso_cohort vc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
    ON hc.hadm_id = vc.hadm_id
    -- approximate 72 hours window by 3 calendar days starting from ICU intime date
    AND hc.chartdate BETWEEN DATE(vc.intime) AND DATE_ADD(DATE(vc.intime), INTERVAL 3 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON d.code = hc.hcpcs_cd
  WHERE
    -- filter HCPCS to likely-imaging items by description (fallback: include when description suggests imaging)
    (
      (d.long_description IS NOT NULL AND (
         LOWER(d.long_description) LIKE '%ct%'
      OR LOWER(d.long_description) LIKE '%mri%'
      OR LOWER(d.long_description) LIKE '%x-ray%'
      OR LOWER(d.long_description) LIKE '%xray%'
      OR LOWER(d.long_description) LIKE '%ultrasound%'
      OR LOWER(d.long_description) LIKE '%radiology%'
      OR LOWER(d.long_description) LIKE '%fluoroscopy%'
      OR LOWER(d.long_description) LIKE '%angiograph%'
      OR LOWER(d.long_description) LIKE '%computed tomography%'
      ))
      OR
      (d.long_description IS NULL AND hc.short_description IS NOT NULL AND (
         LOWER(hc.short_description) LIKE '%ct%'
      OR LOWER(hc.short_description) LIKE '%mri%'
      OR LOWER(hc.short_description) LIKE '%x-ray%'
      OR LOWER(hc.short_description) LIKE '%xray%'
      OR LOWER(hc.short_description) LIKE '%ultrasound%'
      OR LOWER(hc.short_description) LIKE '%radiology%'
      ))
    )
  GROUP BY vc.stay_id
),

-- 5) Procedure counts per admission (entire admission)
procedure_counts AS (
  SELECT
    icu.stay_id,
    COUNT(pi.icd_code) AS procedure_count
  FROM vaso_cohort icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pi.hadm_id = icu.hadm_id
  GROUP BY icu.stay_id
),

-- 6) Readmission within 30 days flag
readmit_30d AS (
  SELECT
    vc.stay_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = vc.subject_id
        AND a2.admittime > vc.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(vc.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30d_flag
  FROM vaso_cohort vc
),

-- 7) Combine counts and compute diagnostic load per stay
stay_metrics AS (
  SELECT
    vc.stay_id,
    vc.subject_id,
    vc.hadm_id,
    vc.intime,
    vc.outtime,
    vc.admittime,
    vc.dischtime,
    vc.hospital_expire_flag,
    COALESCE(lc.lab_count, 0) AS lab_count,
    COALESCE(ic.imaging_count, 0) AS imaging_count,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    COALESCE(r30.readmit_30d_flag, 0) AS readmit_30d_flag,
    -- diagnostic load within 72 hours (repeats included)
    (COALESCE(lc.lab_count, 0) + COALESCE(ic.imaging_count, 0)) AS diagnostic_count,
    -- LOS in days with fraction
    TIMESTAMP_DIFF(vc.dischtime, vc.admittime, SECOND) / 86400.0 AS los_days
  FROM vaso_cohort vc
  LEFT JOIN lab_counts lc ON lc.stay_id = vc.stay_id
  LEFT JOIN imaging_counts ic ON ic.stay_id = vc.stay_id
  LEFT JOIN procedure_counts pc ON pc.stay_id = vc.stay_id
  LEFT JOIN readmit_30d r30 ON r30.stay_id = vc.stay_id
)

-- 8) Assign quartiles and aggregate metrics
SELECT
  quartile,
  COUNT(*) AS n_stays,
  ROUND(AVG(diagnostic_count), 2) AS mean_diagnostic_count,
  ROUND(AVG(procedure_count), 2) AS avg_procedure_count,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag), 4) AS in_hospital_mortality_rate,
  ROUND(AVG(readmit_30d_flag), 4) AS readmission_30d_rate
FROM (
  SELECT
    sm.*,
    NTILE(4) OVER (ORDER BY diagnostic_count ASC) AS quartile
  FROM stay_metrics sm
)
GROUP BY quartile
ORDER BY quartile;