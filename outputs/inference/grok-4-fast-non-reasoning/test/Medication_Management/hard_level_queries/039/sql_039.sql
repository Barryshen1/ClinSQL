WITH cohort AS (
  -- Base cohort: female, age 87-97, with ICH diagnosis
  SELECT 
    DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num <= 5  -- Top 5 diagnoses for broader ICH capture
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code = '431') OR
      (d.icd_version = 'ICD-10' AND LEFT(d.icd_code, 3) = 'I61')
    )
),

med_complexity AS (
  -- Medication administrations in first 48h from inputevents + d_items
  SELECT 
    ie.subject_id, ie.hadm_id,
    ie.itemid
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN cohort c
    ON ie.subject_id = c.subject_id AND ie.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE di.category IN ('base', 'base - medications')
    AND (ie.amount > 0 OR ie.rate > 0)  -- Actual administrations
    AND ie.statusdescription NOT IN ('Cancelled', 'discontinued')
    AND ie.starttime >= c.admittime
    AND ie.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
),

scores AS (
  -- Compute unique drug count per hadm_id
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.anchor_age,
    COUNT(DISTINCT mc.itemid) AS med_complexity_score
  FROM cohort c
  LEFT JOIN med_complexity mc
    ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.anchor_age
),

readmissions AS (
  -- Flag 30-day readmits using full admissions (only for non-mortal index ICH admissions)
  SELECT 
    ich.subject_id, ich.hadm_id AS index_hadm_id,
    COUNT(read_a.hadm_id) > 0 AS has_readmit_30d
  FROM scores ich
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` index_a
    ON ich.hadm_id = index_a.hadm_id 
    AND ich.subject_id = index_a.subject_id
    AND ich.hospital_expire_flag = 0
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` read_a
    ON ich.subject_id = read_a.subject_id
    AND read_a.hadm_id != ich.hadm_id
    AND read_a.admittime > index_a.dischtime
    AND read_a.admittime <= TIMESTAMP_ADD(index_a.dischtime, INTERVAL 30 DAY)
  GROUP BY ich.subject_id, ich.hadm_id
)

-- Final: Stratify by quartiles and aggregate
SELECT 
  quartile,
  COUNT(*) AS num_admissions,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  ROUND(AVG(TIMESTAMP_DIFF(COALESCE(dischtime, TIMESTAMP_ADD(admittime, INTERVAL 1 HOUR)), admittime, HOUR) / 24.0), 2) AS avg_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT)), 2) AS mortality_pct,
  ROUND(100.0 * AVG(CAST(COALESCE(r.has_readmit_30d, FALSE) AS FLOAT)), 2) AS readmit_30d_pct
FROM (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS quartile
  FROM scores
) stratified
LEFT JOIN readmissions r
  ON stratified.hadm_id = r.index_hadm_id
GROUP BY quartile
ORDER BY quartile;