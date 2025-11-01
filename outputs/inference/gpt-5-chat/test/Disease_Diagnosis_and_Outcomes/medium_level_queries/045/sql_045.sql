WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
         adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code
   AND dx.icd_version = dxd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND (
         -- ICD-9 pneumonias
         (dx.icd_version = 9 AND (
           dx.icd_code BETWEEN '481' AND '486'
           OR dx.icd_code = '4870'
           OR dx.icd_code = '5070'
         ))
         -- ICD-10 pneumonias
         OR (dx.icd_version = 10 AND (
           dx.icd_code LIKE 'J13%'
           OR dx.icd_code LIKE 'J14%'
           OR dx.icd_code LIKE 'J15%'
           OR dx.icd_code LIKE 'J16%'
           OR dx.icd_code LIKE 'J17%'
           OR dx.icd_code LIKE 'J18%'
           OR dx.icd_code LIKE 'J690%'
         ))
        )
),
los_flag AS (
  SELECT subject_id, hadm_id, hospital_expire_flag,
         CASE WHEN DATETIME_DIFF(dischtime, admittime, DAY) <= 7 THEN 'LOS<=7'
              ELSE 'LOS>7' END AS los_group
  FROM pneumonia_admissions
),
icu_day1 AS (
  SELECT hadm_id,
         MIN(intime) AS first_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
icu_day1_flag AS (
  SELECT l.hadm_id,
         CASE WHEN DATETIME_DIFF(first_intime, p.admittime, HOUR) <= 24 THEN 1 ELSE 0 END AS day1_icu
  FROM icu_day1 l
  JOIN pneumonia_admissions p
    ON l.hadm_id = p.hadm_id
),
vent_flag AS (
  SELECT DISTINCT ie.hadm_id, 1 AS mech_vent
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ventilation%'
    AND LOWER(di.label) LIKE '%invasive%'
),
vasopressor_flag AS (
  SELECT DISTINCT ie.hadm_id, 1 AS vasopressor
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%norepinephrine%'
     OR LOWER(di.label) LIKE '%epinephrine%'
     OR LOWER(di.label) LIKE '%phenylephrine%'
     OR LOWER(di.label) LIKE '%dopamine%'
     OR LOWER(di.label) LIKE '%vasopressin%'
),
rrt_flag AS (
  SELECT DISTINCT pe.hadm_id, 1 AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%renal replacement%'
     OR LOWER(di.label) LIKE '%crrt%'
)
SELECT lf.los_group,
       COUNT(*) AS n_admissions,
       ROUND(AVG(lf.hospital_expire_flag)*100,1) AS mortality_pct,
       ROUND(AVG(IFNULL(id1.day1_icu,0))*100,1) AS day1_icu_pct,
       ROUND(AVG(IFNULL(v.mech_vent,0))*100,1) AS mech_vent_pct,
       ROUND(AVG(IFNULL(vp.vasopressor,0))*100,1) AS vasopressor_pct,
       ROUND(AVG(IFNULL(r.rt,0))*100,1) AS rrt_pct
FROM los_flag lf
LEFT JOIN icu_day1_flag id1
  ON lf.hadm_id = id1.hadm_id
LEFT JOIN vent_flag v
  ON lf.hadm_id = v.hadm_id
LEFT JOIN vasopressor_flag vp
  ON lf.hadm_id = vp.hadm_id
LEFT JOIN (
  SELECT hadm_id, MAX(rrt) AS rt
  FROM rrt_flag
  GROUP BY hadm_id
) r
  ON lf.hadm_id = r.hadm_id
GROUP BY lf.los_group
ORDER BY lf.los_group;