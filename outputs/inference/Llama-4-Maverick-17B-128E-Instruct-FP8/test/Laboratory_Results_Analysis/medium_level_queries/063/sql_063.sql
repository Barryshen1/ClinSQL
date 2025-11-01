WITH 
troponin_i_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin-I%' OR label LIKE '%Troponin I%'
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 84 AND 94
),
acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM eligible_patients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE icd.long_title LIKE '%Acute coronary syndrome%' OR icd.long_title LIKE '%Myocardial infarction%'
),
first_troponin_i AS (
  SELECT a.hadm_id, l.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) as troponin_seq
  FROM acs_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM troponin_i_itemid)
),
troponin_i_uln AS (
  SELECT MIN(ref_range_upper) as uln
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid IN (SELECT itemid FROM troponin_i_itemid) AND ref_range_upper IS NOT NULL
),
elevated_troponin_i AS (
  SELECT f.hadm_id, f.valuenum
  FROM first_troponin_i f
  WHERE f.troponin_seq = 1 AND f.valuenum > (SELECT uln FROM troponin_i_uln)
)
SELECT 
  COUNT(*) as count,
  AVG(valuenum) as mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] as median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] as q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] as q3
FROM elevated_troponin_i;