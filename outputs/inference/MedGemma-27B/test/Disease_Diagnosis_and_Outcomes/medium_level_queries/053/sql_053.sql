SELECT
    a.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  WHERE
    di.seq_num > 1 -- Exclude primary diagnosis
  GROUP BY
    a.hadm_id;