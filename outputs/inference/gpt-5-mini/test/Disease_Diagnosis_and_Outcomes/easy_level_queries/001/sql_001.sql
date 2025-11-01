WITH
-- Admissions that have at least one diagnosis matching our UGIB text patterns
admissions_with_ugib AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(dd.long_title),
      r'(hematemesis|melena|upper gastrointestinal|upper gi|gastrointestinal hemorrhage|gastrointestinal haemorrhage|gastric ulcer.*hemorrhag|duodenal ulcer.*hemorrhag)')
),
-- Admissions that have at least one diagnosis matching COPD exacerbation text patterns
admissions_with_copd_exacerb AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title IS NOT NULL
    -- require both a COPD indicator and an exacerbation indicator in the long_title
    AND REGEXP_CONTAINS(LOWER(dd.long_title), r'(copd|chronic obstructive)')
    AND REGEXP_CONTAINS(LOWER(dd.long_title), r'(exacerb)')
)

SELECT
  COUNT(DISTINCT a.hadm_id) AS admissions_count,
  COUNT(DISTINCT a.subject_id) AS unique_patient_count,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0), 2) AS avg_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
-- Require membership in both diagnosis sets
JOIN admissions_with_ugib u ON a.hadm_id = u.hadm_id
JOIN admissions_with_copd_exacerb c ON a.hadm_id = c.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 86 AND 96
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;