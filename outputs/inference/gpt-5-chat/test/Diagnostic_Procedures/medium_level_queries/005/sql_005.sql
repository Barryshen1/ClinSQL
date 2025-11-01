WITH ischemic_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN MIN(d.seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS dx_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      -- ICD-9 ischemic stroke
      (d.icd_version = 9 AND (
         d.icd_code LIKE '433%' OR
         d.icd_code LIKE '434%' OR
         d.icd_code = '436'
      ))
      -- ICD-10 ischemic stroke
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
  GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
),
los_bins AS (
  SELECT
    ic.*,
    DATETIME_DIFF(ic.dischtime, ic.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(ic.dischtime, ic.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4_days'
      WHEN DATETIME_DIFF(ic.dischtime, ic.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8_days'
      ELSE NULL
    END AS los_bin
  FROM ischemic_cohort ic
),
proc_counts AS (
  SELECT
    lb.subject_id,
    lb.hadm_id,
    COUNT(*) AS num_diag_procs
  FROM los_bins lb
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON lb.subject_id = pi.subject_id
   AND lb.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code
   AND pi.icd_version = dpi.icd_version
  WHERE LOWER(dpi.long_title) LIKE '%diagnostic%'
  GROUP BY lb.subject_id, lb.hadm_id
)
SELECT
  l.los_bin,
  l.dx_type,
  AVG(pc.num_diag_procs) AS mean_diag_procs,
  MIN(pc.num_diag_procs) AS min_diag_procs,
  MAX(pc.num_diag_procs) AS max_diag_procs
FROM los_bins l
JOIN proc_counts pc
  ON l.subject_id = pc.subject_id
 AND l.hadm_id = pc.hadm_id
WHERE l.los_bin IS NOT NULL
GROUP BY l.los_bin, l.dx_type
ORDER BY l.los_bin, l.dx_type;