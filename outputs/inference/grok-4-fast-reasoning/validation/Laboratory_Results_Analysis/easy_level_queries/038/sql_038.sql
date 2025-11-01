WITH stroke_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('43301', '43311', '43321', '43331', '43391',
                                                   '43401', '43411', '43491', '436'))
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
)
SELECT MIN(le.valuenum) AS min_hemoglobin
FROM stroke_admissions sa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON sa.hadm_id = le.hadm_id
WHERE le.itemid = 51222
  AND le.valuenum IS NOT NULL
  AND le.valueuom = 'g/dL'
  AND le.charttime >= sa.admittime
  AND le.charttime <= TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR);