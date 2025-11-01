SELECT
  AVG(num_procedures) AS avg_distinct_valve_procedures_per_patient
FROM (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(CAST(pr.hadm_id AS STRING), '_', CAST(pr.seq_num AS STRING))) AS num_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND (UPPER(d.long_title) LIKE '%VALVE%'
      OR UPPER(d.long_title) LIKE '%VALVULAR%')
    AND (UPPER(d.long_title) LIKE '%REPAIR%'
      OR UPPER(d.long_title) LIKE '%REPLACEMENT%')
    AND EXTRACT(YEAR FROM pr.chartdate) - (p.anchor_year - p.anchor_age) BETWEEN 42 AND 52
  GROUP BY
    p.subject_id
) AS patient_procedures;