SELECT
  MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days,
  COUNT(*) AS admissions_considered
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id
  AND a.hadm_id = d.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON d.icd_code = dicd.icd_code
  AND d.icd_version = dicd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 49 AND 59
  AND d.seq_num = 1
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
  AND (
    -- explicit "upper" + GI/stomach/esophagus/duodenal terms
    (REGEXP_CONTAINS(LOWER(dicd.long_title), r'upper')
     AND REGEXP_CONTAINS(LOWER(dicd.long_title), r'(gastrointestinal|gi|gastro|stomach|esophagus|esophageal|duodenal)'))
    -- or common synonyms/ presentations of upper GI bleeding
    OR REGEXP_CONTAINS(LOWER(dicd.long_title), r'hematemesis')
    OR REGEXP_CONTAINS(LOWER(dicd.long_title), r'melena')
  );