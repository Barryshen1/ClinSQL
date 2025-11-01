SELECT STDDEV(avg_creatinine) AS std_creatinine_first_24hr
FROM (
    SELECT l.hadm_id, AVG(l.valuenum) AS avg_creatinine
    FROM physionet-data.mimiciv_3_1_hosp.labevents l
    JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d
        ON l.itemid = d.itemid
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a
        ON l.hadm_id = a.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
        ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
        ON a.hadm_id = di.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.anchor_age = 90
      AND p.gender = 'M'
      AND LOWER(dd.long_title) LIKE '%copd%'
      AND LOWER(d.label) = 'creatinine'
      AND LOWER(d.fluid) = 'blood'
      AND l.valuenum IS NOT NULL
      AND l.charttime >= a.admittime
      AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
    GROUP BY l.hadm_id
) subquery;