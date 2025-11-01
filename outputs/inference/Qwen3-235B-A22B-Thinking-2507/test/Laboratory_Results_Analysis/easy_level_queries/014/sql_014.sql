WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) = 45
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_version = 10
        AND d.icd_code IN (
          'K920', 'K921', 'K922', 'K625', 'I850', 'I8511', 'I8510', 
          'I8521', 'I8520', 'I864', 'K648', 'K640', 'K644'
        )
    )
),
discharge_hemoglobin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS hemoglobin,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime DESC
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  INNER JOIN filtered_admissions f
    ON l.hadm_id = f.hadm_id
  WHERE 
    d.label = 'Hemoglobin'
    AND l.valueuom = 'g/dL'
    AND DATE(l.charttime) = DATE(f.dischtime)
)
SELECT 
  APPROX_QUANTILES(hemoglobin, 1000)[OFFSET(750)] AS p75_hemoglobin
FROM discharge_hemoglobin
WHERE rn = 1;