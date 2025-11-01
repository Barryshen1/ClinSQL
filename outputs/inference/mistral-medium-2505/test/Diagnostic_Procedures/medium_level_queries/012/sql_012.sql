WITH
-- Get ACS admissions with patient info
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    -- Calculate age at admission (anchor_age is age at anchor_year)
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 35 AND 45
    -- ACS ICD codes (ICD-9 and ICD-10)
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410.%') OR
      (d.icd_version = 9 AND d.icd_code = '411.1') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I22.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I23.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I24.%')
    )
),

-- Count ultrasounds per admission (from HCPCS events)
ultrasound_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT hcpcs_cd) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    -- HCPCS codes for ultrasounds (including echocardiography)
    hcpcs_cd IN (
      '76801', '76802', '76805', '76810', '76811', '76815', '76816', '76817',
      '76820', '76821', '76825', '76826', '76827', '76828', '76830',
      '93306', '93307', '93308', '93312', '93313', '93314', '93315', '93316', '93317', '93318',
      '93320', '93321', '93325', '93350', '93351', '93352'
    )
  GROUP BY
    hadm_id
),

-- Combine with LOS categories
final_data AS (
  SELECT
    aa.hadm_id,
    aa.los_days,
    CASE
      WHEN aa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN aa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_category,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
  FROM
    acs_admissions aa
  LEFT JOIN
    ultrasound_counts uc ON aa.hadm_id = uc.hadm_id
  WHERE
    aa.los_days BETWEEN 1 AND 7
)

-- Final aggregation
SELECT
  los_category,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM
  final_data
WHERE
  los_category IS NOT NULL
GROUP BY
  los_category
ORDER BY
  los_category;