SELECT MAX(los_days) AS max_length_of_stay_days
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE d.seq_num = 1
    AND d.icd_code IN ('578.0', '578.1')  -- primary dx upper GI bleed (hematemesis, melena)
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
) AS sub;