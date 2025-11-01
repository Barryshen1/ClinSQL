WITH index_candidates AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
   AND di.seq_num = 1  -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.admission_type = 'EMERGENCY'  -- admitted via ED
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND (d.long_title LIKE '%femoral neck fracture%' OR d.long_title LIKE '%hip fracture%')
    AND a.dischtime IS NOT NULL
),

index_with_read AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.admittime,
    ic.dischtime,
    ic.index_los_days,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ic.subject_id
        AND a2.hadm_id <> ic.hadm_id
        AND a2.admittime > ic.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ic.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30
  FROM index_candidates ic
)

SELECT
  AVG(IF(readmit_30, 1, 0)) AS readmission_rate_30day,
  (SELECT APPROX_QUANTILES(index_los_days, 100)[OFFSET(50)]
     FROM index_with_read iw
     WHERE iw.readmit_30 = TRUE) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(index_los_days, 100)[OFFSET(50)]
     FROM index_with_read iw
     WHERE iw.readmit_30 = FALSE) AS median_los_nonreadmitted_days,
  (SELECT 100.0 * COUNTIF(index_los_days > 8) / COUNT(*)
     FROM index_with_read) AS percent_stays_gt8_days
FROM index_with_read;