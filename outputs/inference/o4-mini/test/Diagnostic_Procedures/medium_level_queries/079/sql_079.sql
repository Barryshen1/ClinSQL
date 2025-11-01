WITH lower_gi AS (
  -- Identify admissions with lower GI bleed diagnoses
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    p.anchor_age,
    p.gender,
    -- Flag primary vs secondary
    CASE WHEN MIN(d.seq_num) = 1 THEN 'primary'
         ELSE 'secondary'
    END AS diag_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    -- ICD9 & ICD10 codes for lower GI bleed
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5781','5789'))
      OR (d.icd_version = 10 AND d.icd_code IN ('K62.5','K92.1','K92.2'))
    )
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age, p.gender
),
imaging_counts AS (
  -- Count CT/X-ray studies per admission
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.long_description) LIKE '%ct%'
     OR LOWER(d.long_description) LIKE '%x-ray%'
     OR LOWER(d.long_description) LIKE '%xray%'
  GROUP BY h.hadm_id
)
SELECT
  CASE
    WHEN lg.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN lg.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  lg.diag_type,
  AVG(IFNULL(ic.imaging_count, 0)) AS mean_imaging_per_admission,
  COUNT(*) AS admissions_count
FROM lower_gi lg
LEFT JOIN imaging_counts ic
  ON lg.hadm_id = ic.hadm_id
WHERE lg.los_days BETWEEN 1 AND 7
GROUP BY los_category, lg.diag_type
ORDER BY los_category, lg.diag_type;