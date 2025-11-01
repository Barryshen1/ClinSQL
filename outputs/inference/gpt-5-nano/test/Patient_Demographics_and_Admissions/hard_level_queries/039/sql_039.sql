WITH index_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS index_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
   AND di.seq_num = 1  -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND UPPER(a.insurance) LIKE '%MEDICARE%'
    AND (a.admission_location = 'ED' OR a.admission_type = 'EMERGENCY')
    AND UPPER(dd.long_title) LIKE '%ACUTE RESPIRATORY FAILURE%'
),
readiness AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.admittime,
    ic.dischtime,
    ic.index_los,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ic.subject_id
        AND a2.hadm_id <> ic.hadm_id
        AND a2.admittime > ic.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ic.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_flag
  FROM index_cohort ic
)

SELECT
  100.0 * SUM(CASE WHEN readmit_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS readmission_rate_percent,
  (SELECT
     APPROX_QUANTILES(index_los, 100)[OFFSET(50)]
   FROM readiness r
   WHERE r.readmit_flag = 1) AS median_index_los_readmitted,
  (SELECT
     APPROX_QUANTILES(index_los, 100)[OFFSET(50)]
   FROM readiness r
   WHERE r.readmit_flag = 0) AS median_index_los_not_readmitted,
  100.0 * SUM(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt_9
FROM readiness;