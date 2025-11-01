WITH ACS_Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.hadm_id IN (
      SELECT
        hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        icd_code LIKE 'I21%' -- ACS codes
        AND seq_num = 1 -- Primary diagnosis
    )
),
Radiography_Counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS radiography_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON a.hadm_id = hc.hadm_id
  WHERE
    a.hadm_id IN (
      SELECT
        hadm_id
      FROM ACS_Admissions
    )
    AND hc.hcpcs_cd LIKE '7%' -- Radiography/CT codes
  GROUP BY
    a.hadm_id
),
Stay_Duration AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS stay_duration
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IN (
      SELECT
        hadm_id
      FROM ACS_Admissions
    )
)
SELECT
  CASE
    WHEN sd.stay_duration BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN sd.stay_duration BETWEEN 5 AND 8
    THEN '5-8 days'
    ELSE 'Other'
  END AS stay_duration_group,
  d.icd_code,
  AVG(rc.radiography_count) AS mean_radiography_count,
  MIN(rc.radiography_count) AS min_radiography_count,
  MAX(rc.radiography_count) AS max_radiography_count
FROM ACS_Admissions AS acs
INNER JOIN Radiography_Counts AS rc
  ON acs.hadm_id = rc.hadm_id
INNER JOIN Stay_Duration AS sd
  ON acs.hadm_id = sd.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON acs.hadm_id = d.hadm_id
WHERE
  d.seq_num = 1 -- Primary diagnosis
GROUP BY
  stay_duration_group,
  d.icd_code
ORDER BY
  stay_duration_group,
  d.icd_code;